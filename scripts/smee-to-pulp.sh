#!/usr/bin/env bash

set -x

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat pipe errors properly
set -o pipefail

# --- Default Settings ---
DEFAULT_PULP_USER="admin"
DEFAULT_PULP_PASSWORD="password"
DEFAULT_PULP_BASE_URL="https://pulp03.lab.lightbitslabs.com"
REPO_NAME="tinkerbell-hook" # Keep repository name constant for now
DISTRIBUTION_NAME="tinkerbell/hook"

# --- Helper Functions ---
usage() {
    echo "Usage: $0 [OPTIONS] <VMLINUZ_PATH> <INITRAMFS_PATH>"
    echo
    echo "Uploads vmlinuz and initramfs files to a Pulp file repository."
    echo
    echo "Arguments:"
    echo "  <VMLINUZ_PATH>     Path to the vmlinuz file."
    echo "  <INITRAMFS_PATH>   Path to the initramfs file."
    echo
    echo "Options:"
    echo "  --username USER    Pulp username (default: ${DEFAULT_PULP_USER})"
    echo "  --password PASS    Pulp password (default: ********)"
    echo "  --base-url URL     Pulp base URL (default: ${DEFAULT_PULP_BASE_URL})"
    echo "  -h, --help         Show this help message."
    exit 1
}

# --- Main Logic Function ---
main() {
    local vmlinuz_path="$1"
    local initramfs_path="$2"
    local pulp_user="$3"
    local pulp_password="$4"
    local pulp_base_url="$5"

    echo "--- Starting Pulp Update Process ---"
    echo "VMLINUZ File: $vmlinuz_path"
    echo "INITRAMFS File: $initramfs_path"
    echo "Pulp URL: $pulp_base_url"
    echo "Pulp User: $pulp_user"
    echo "Repository Name: $REPO_NAME"
    echo "------------------------------------"


    # Check if input files exist
    if [ ! -f "$vmlinuz_path" ]; then
        echo "Error: VMLINUZ file not found at $vmlinuz_path"
        exit 1
    fi

    if [ ! -f "$initramfs_path" ]; then
        echo "Error: INITRAMFS file not found at $initramfs_path"
        exit 1
    fi

    # Check for required commands
    if ! command -v git &> /dev/null; then
        echo "Error: 'git' command not found. Please install git."
        exit 1
    fi
     if ! command -v pulp &> /dev/null; then
        echo "Error: 'pulp' command not found. Please install pulp-cli."
        exit 1
    fi
     if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' command not found. Please install jq."
        exit 1
    fi

    local git_version
    git_version=$(git describe --tags --abbrev=8 --always --long --dirty || echo "unknown-git-version") # Handle case where not in git repo

    # Construct base Pulp arguments - Use arrays for safer handling of arguments
    local pulp_args=(
        --username "$pulp_user"
        --password "$pulp_password"
        --base-url "$pulp_base_url"
    )

    echo "Checking for repository '$REPO_NAME'..."
    # Use pulp command exit status to check existence, safer than parsing output
    if ! pulp "${pulp_args[@]}" file repository show --name "$REPO_NAME" > /dev/null 2>&1; then
        echo "Repository '$REPO_NAME' not found. Creating..."
        pulp "${pulp_args[@]}" file repository create --name "$REPO_NAME" --autopublish
        echo "Repository '$REPO_NAME' created."
    else
        echo "Repository '$REPO_NAME' found."
    fi

    echo "Listing current content in repository '$REPO_NAME'..."
    local raw_pulp_output
    local remove_content

    # Step 1: Query Pulp and capture raw output
    # Use set +e temporarily if you want to capture non-zero exit codes from pulp without exiting the script immediately
    # set +e
    raw_pulp_output=$(pulp "${pulp_args[@]}" file repository content list --repository "$REPO_NAME" --limit 10000)
    # pulp_exit_code=$?
    # set -e # Re-enable exit on error

    # Optional: Check pulp command exit code if needed
    # if [ $pulp_exit_code -ne 0 ]; then
    #     echo "Error: pulp command failed with exit code $pulp_exit_code" >&2
    #     echo "Output: $raw_pulp_output" >&2
    #     exit 1
    # fi

    echo "Raw output received from Pulp: ${raw_pulp_output}" # For debugging

    # Step 2 & 3: Check if the output is an empty array string
    # Trim whitespace for comparison (though unlikely from pulp)
    shopt -s extglob # Enable extended globbing for trimming
    trimmed_output=${raw_pulp_output##*( )} # Trim leading whitespace
    trimmed_output=${trimmed_output%%*( )} # Trim trailing whitespace
    shopt -u extglob # Disable extended globbing

    if [[ "$trimmed_output" == "[]" ]]; then
        echo "Detected empty content list from Pulp."
        remove_content="[]"
    elif [[ -z "$trimmed_output" || "$trimmed_output" == "null" ]]; then
        # Handle cases where output might be empty string or literal "null"
        echo "Detected empty or null content list from Pulp."
        remove_content="[]"
    else
        # Step 4: Assume standard object format and process with jq
        echo "Processing non-empty content list with jq..."
        # This jq filter now assumes the input is like {"results": [...]}
        remove_content=$(echo "$raw_pulp_output" | jq -c '. | map(select(. != null) | {"relative_path": .relative_path, "sha256": .sha256})')

        # Add error check for jq itself
        if [ $? -ne 0 ]; then
            echo "Error: jq failed to process the following Pulp output:" >&2
            echo "$raw_pulp_output" >&2
            # Setting remove_content to empty array might be safer than exiting
            # depending on desired behavior, but exiting is clearer on failure.
            exit 1
        fi

        # Handle case where jq might output 'null' if .results was null in the JSON object
        if [[ "$remove_content" == "null" ]]; then
             echo "Warning: jq processing resulted in 'null', defaulting to '[]'."
             remove_content="[]"
        fi
    fi

    echo "Content currently in repository (to be removed): $remove_content"

    local add_content_json='['
    local first_item=true

    echo "Processing input files for upload..."
    for file in "$vmlinuz_path" "$initramfs_path"; do
        echo "Processing file: $file"
        local artifact_basename
        artifact_basename=$(basename "$file")

        artifact_sha256=$(sha256sum "$file" | awk '{print $1}')
        echo "  Artifact basename: $artifact_basename"
        echo "  Artifact SHA256: $artifact_sha256"

        if [ -z "$artifact_sha256" ]; then
            echo "Error: Failed to compute SHA256 for $file"
            exit 1
        fi
        # Check if the artifact already exists in the repository
        local existing_content
        existing_content=$(pulp "${pulp_args[@]}" file content list --relative-path $artifact_basename --sha256 $artifact_sha256 --limit 1 | jq -r '.[0]?.pulp_href // ""')
        # Check if the content not exists in the repository, and if so, upload it
        if [ -z "$existing_content" ]; then
            echo "  Artifact $artifact_basename with sha256 $artifact_sha256 does not exist in the repository."
            # Upload the artifact if it doesn't exist
            echo "  Creating content unit..."
            local content_href
            content_href=$(pulp "${pulp_args[@]}" file content upload --relative-path "$artifact_basename" --file "$file" | jq -re '.pulp_href')
            # --sha256 $artifact_sha256 is often redundant if artifact is specified by href, but kept for parity
            echo "  Content HREF: $content_href"
            # pulp "${pulp_args[@]}" file content show --href "$content_href" # Optional: Show content details
        else
            # If it exists, we can skip the upload
            # Note: This check is done before uploading to avoid unnecessary uploads
            # and to ensure we don't overwrite existing content.
            # If you want to overwrite, you can remove this check.
            echo "  Artifact $artifact_basename with sha256 $artifact_sha256 already exists in the repository. Skipping upload."
        fi

        # Build JSON string for add_content
        if [ "$first_item" = true ]; then
            first_item=false
        else
            add_content_json+=','
        fi
        # Use jq for safer JSON string construction within the loop item
        local item_json
        item_json=$(jq -n --arg sha "$artifact_sha256" --arg path "$artifact_basename" '{"sha256": $sha, "relative_path": $path}')
        add_content_json+="$item_json"

    done
    add_content_json+=']'
    echo "Content to be added: $add_content_json"

    echo "Updating repository content..."
    pulp "${pulp_args[@]}" file repository content modify --repository "$REPO_NAME" --remove-content "$remove_content" --add-content "$add_content_json"

    echo "Repository update complete. Current version details:"
    pulp "${pulp_args[@]}" file repository version show --repository "$REPO_NAME" # --limit 1 # Show latest version

    local latest_repo_version_href
    latest_repo_version_href=$(pulp "${pulp_args[@]}" file repository version list --repository "$REPO_NAME" --limit 1 | jq -re '.[0].pulp_href')
    if [ -z "$latest_repo_version_href" ]; then
        echo "Error: Could not determine the latest repository version HREF."
        exit 1
    fi
    echo "Latest repository version HREF: $latest_repo_version_href"

    local latest_repo_version_number
    latest_repo_version_number=$(pulp "${pulp_args[@]}" file repository version list --repository "$REPO_NAME" --limit 1 | jq -re '.[0]?.number // ""')
    if [ -z "$latest_repo_version_number" ]; then
        echo "Error: Could not determine the latest repository version number."
        exit 1
    fi


    local publication_href

    echo "Checking for existing publication..."
    # Get href of the first publication matching the latest repo version
    publication_href=$(pulp "${pulp_args[@]}" file publication list --repository-version "$latest_repo_version_href" --limit 1 | jq -re '.[0]?.pulp_href // ""')

    if [ -z "$publication_href" ]; then
        echo "No publication found for the latest repository version. Creating..."
        publication_href=$(pulp "${pulp_args[@]}" file publication create --repository "$REPO_NAME" --version "$latest_repo_version_number" | jq -re '.pulp_href')
        echo "Publication created. HREF: $publication_href"
    else
        echo "Existing publication found. HREF: $publication_href"
    fi
    # pulp "${pulp_args[@]}" show --href "$publication_href" # Optional: Show publication details


    local distribution_name="$DISTRIBUTION_NAME"
    local distribution_labels
    distribution_labels=$(jq -n --arg version "$git_version" '{"version": $version}')

    echo "Checking for distribution '$distribution_name'..."
    if ! pulp "${pulp_args[@]}" file distribution show --name "$distribution_name" > /dev/null 2>&1; then
        echo "Distribution '$distribution_name' not found. Creating..."
        pulp "${pulp_args[@]}" file distribution create --name "$distribution_name" --base-path "$distribution_name" --publication "$publication_href" --labels "$distribution_labels"
        echo "Distribution created."
    else
        echo "Distribution '$distribution_name' found. Updating..."
        # Update distribution to point to the specific publication created/found for the latest repo version
        # and update labels
        pulp "${pulp_args[@]}" file distribution update --name "$distribution_name" --publication "$publication_href" --labels "$distribution_labels"
        # Note: Updating distribution with --repository is deprecated/removed in newer pulp versions
        # Pointing to the specific publication is the correct way.
        echo "Distribution updated."
    fi

    echo "Showing final distribution details:"
    pulp "${pulp_args[@]}" file distribution show --name "$distribution_name"

    echo "--- Pulp Update Process Finished Successfully ---"
}

# --- Argument Parsing ---
pulp_user="${DEFAULT_PULP_USER}"
pulp_password="${DEFAULT_PULP_PASSWORD}"
pulp_base_url="${DEFAULT_PULP_BASE_URL}"
positional_args=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            if [[ -z "$2" || "$2" == -* ]]; then echo "Error: --username requires an argument." >&2; usage; fi
            pulp_user="$2"
            shift # past argument
            shift # past value
            ;;
        --password)
            if [[ -z "$2" || "$2" == -* ]]; then echo "Error: --password requires an argument." >&2; usage; fi
            pulp_password="$2"
            shift # past argument
            shift # past value
            ;;
        --base-url)
            if [[ -z "$2" || "$2" == -* ]]; then echo "Error: --base-url requires an argument." >&2; usage; fi
            pulp_base_url="$2"
            shift # past argument
            shift # past value
            ;;
        -h|--help)
            usage
            ;;
        --) # end argument parsing
            shift
            positional_args+=("$@") # Add remaining args to positional
            break
            ;;
        -*) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            usage
            ;;
        *) # preserve positional arguments
            positional_args+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
# set -- "${positional_args[@]}" # Not needed if we pass them directly

# Validate positional arguments
if [ "${#positional_args[@]}" -ne 2 ]; then
    echo "Error: Incorrect number of arguments. Requires VMLINUZ and INITRAMFS paths." >&2
    usage
fi

vmlinuz_path="${positional_args[0]}"
initramfs_path="${positional_args[1]}"

# --- Script Execution ---
# Call the main function, passing parsed arguments
main "$vmlinuz_path" "$initramfs_path" "$pulp_user" "$pulp_password" "$pulp_base_url"

exit 0
