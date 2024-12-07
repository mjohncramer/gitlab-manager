#!/bin/bash

# ================================
# GitLab Management Script with Colors
# Enhanced for better readability and professionalism
# ================================

# ================================
# Color Definitions
# ================================
# Reset
RESET='\033[0m'

# Regular Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'

# Bold
BOLD='\033[1m'

# ================================
# GitLab API Configuration
# ================================
GITLAB_API_URL="https://gitlab.com/api/v4"
GITLAB_TOKEN=""  # **Security Note**: Avoid hardcoding tokens in scripts. Use environment variables or secure storage.

# Debug mode: Set to "enable" to see raw JSON responses and debug logs
DEBUG="disable"

# Navigation stack
declare -a group_stack

# ================================
# Helper Functions for Colored Output
# ================================
# Function to display informational messages
info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

# Function to display success messages
success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $*"
}

# Function to display warning messages
warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $*"
}

# Function to display error messages
error() {
    echo -e "${RED}[ERROR]${RESET} $*"
}

# Function to display debug messages
debug_log() {
    if [[ "$DEBUG" == "enable" ]]; then
        echo -e "${CYAN}[DEBUG]${RESET} $*"
    fi
}

# ================================
# Fetch top-level groups
# ================================
fetch_groups() {
    debug_log "Fetching top-level groups..."
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                     "$GITLAB_API_URL/groups?top_level_only=true")
    debug_log "Raw API response for groups: $response"

    if echo "$response" | jq empty 2>/dev/null; then
        echo "$response" | jq -r '.[] | "\(.id) \(.name)"'
    else
        error "Failed to fetch groups. API response is not valid JSON."
        return 1
    fi
}

# ================================
# Fetch subgroups for a given group ID
# ================================
fetch_subgroups() {
    local group_id="$1"
    debug_log "Fetching subgroups for group ID $group_id..."
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                     "$GITLAB_API_URL/groups/$group_id/subgroups")
    debug_log "Raw API response for subgroups: $response"

    if echo "$response" | jq empty 2>/dev/null; then
        echo "$response" | jq -r '.[] | "\(.id) \(.name)"'
    else
        error "Failed to fetch subgroups. API response is not valid JSON."
        return 1
    fi
}

# ================================
# Fetch projects for a given group ID
# ================================
fetch_projects() {
    local group_id="$1"
    debug_log "Fetching projects for group ID $group_id..."
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                     "$GITLAB_API_URL/groups/$group_id/projects")
    debug_log "Raw API response for projects: $response"

    if echo "$response" | jq empty 2>/dev/null; then
        echo "$response" | jq -r '.[] | "\(.id) \(.name)"'
    else
        error "Failed to fetch projects. API response is not valid JSON."
        return 1
    fi
}

# ================================
# List all groups and projects
# ================================
list_all_groups_and_projects() {
    info "Listing all groups, subgroups, and projects..."

    # Fetch all top-level groups
    local groups
    groups=$(fetch_groups)
    if [[ -z "$groups" ]]; then
        warning "No groups found."
        return
    fi

    # Recursive function to list subgroups and projects
    list_subgroups_and_projects() {
        local parent_group_id="$1"
        local indent="$2"

        # Fetch subgroups for the given group
        local subgroups
        subgroups=$(fetch_subgroups "$parent_group_id")
        if [[ -n "$subgroups" ]]; then
            echo -e "${indent}${MAGENTA}Subgroups:${RESET}"
            echo "$subgroups" | while read -r subgroup; do
                local subgroup_id
                local subgroup_name
                subgroup_id=$(echo "$subgroup" | cut -d ' ' -f1)
                subgroup_name=$(echo "$subgroup" | cut -d ' ' -f2-)
                echo -e "${indent}  - ${GREEN}$subgroup_name${RESET}"

                # Fetch and display projects in the current subgroup
                local projects
                projects=$(fetch_projects "$subgroup_id")
                if [[ -n "$projects" ]]; then
                    echo -e "${indent}    ${CYAN}Projects:${RESET}"
                    echo "$projects" | while read -r project; do
                        local project_name
                        project_name=$(echo "$project" | cut -d ' ' -f2-)
                        echo -e "${indent}      - $project_name"
                    done
                else
                    echo -e "${indent}    ${YELLOW}No projects found in this subgroup.${RESET}"
                fi

                # Recursively list subgroups and their projects
                list_subgroups_and_projects "$subgroup_id" "${indent}    "
            done
        else
            echo -e "${indent}${YELLOW}No subgroups found.${RESET}"
        fi
    }

    # Iterate through each top-level group
    echo -e "${MAGENTA}Top-Level Groups:${RESET}"
    mapfile -t group_array < <(echo "$groups")
    for group_entry in "${group_array[@]}"; do
        local group_id
        local group_name
        group_id=$(echo "$group_entry" | cut -d ' ' -f1)
        group_name=$(echo "$group_entry" | cut -d ' ' -f2-)

        echo -e "${BOLD}Group: ${RESET}$group_name"

        # Fetch and display projects in the current group
        local projects
        projects=$(fetch_projects "$group_id")
        if [[ -n "$projects" ]]; then
            echo -e "  ${CYAN}Projects:${RESET}"
            echo "$projects" | while read -r project; do
                local project_name
                project_name=$(echo "$project" | cut -d ' ' -f2-)
                echo -e "    - $project_name"
            done
        else
            echo -e "  ${YELLOW}No projects found in this group.${RESET}"
        fi

        # List subgroups and their projects recursively
        list_subgroups_and_projects "$group_id" "  "
        echo
    done
}

# ================================
# Create a subgroup
# ================================
create_subgroup() {
    local parent_group_id="$1"
    read -rp "$(echo -e "${YELLOW}Enter subgroup name: ${RESET}")" name
    read -rp "$(echo -e "${YELLOW}Enter subgroup description (optional): ${RESET}")" description
    read -rp "$(echo -e "${YELLOW}Enter subgroup visibility (public, internal, private): ${RESET}")" visibility

    # Automatically generate the path from the name
    path=$(echo "$name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    json_payload=$(cat <<EOF
{
  "name": "$name",
  "path": "$path",
  "description": "$description",
  "visibility": "$visibility",
  "parent_id": "$parent_group_id"
}
EOF
)

    debug_log "Creating subgroup with payload: $json_payload"

    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                     --header "Content-Type: application/json" \
                     --data "$json_payload" \
                     "$GITLAB_API_URL/groups")
    debug_log "Raw API response for subgroup creation: $response"

    if echo "$response" | jq empty 2>/dev/null; then
        subgroup_name=$(echo "$response" | jq -r '.name')
        success "Subgroup '${subgroup_name}' created successfully."
    else
        error "Failed to create subgroup. API response: $response"
    fi
}

# ================================
# List and clone a project
# ================================
list_and_clone_project() {
    local group_id="$1"
    projects=$(fetch_projects "$group_id")
    if [[ -z "$projects" ]]; then
        warning "No projects available in the current group."
        return
    fi

    info "Available Projects:"
    mapfile -t project_array < <(echo "$projects")
    for i in "${!project_array[@]}"; do
        project_name=$(echo "${project_array[i]}" | cut -d ' ' -f2-)
        echo -e "${CYAN}$((i + 1)).${RESET} $project_name"
    done

    read -rp "$(echo -e "${YELLOW}Choose a project to clone (0 to cancel): ${RESET}")" choice
    if (( choice == 0 )); then
        info "Cloning canceled."
        return
    elif (( choice > 0 && choice <= ${#project_array[@]} )); then
        selected_project="${project_array[choice - 1]}"
        project_id=$(echo "$selected_project" | cut -d ' ' -f1)

        project_url=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                            "$GITLAB_API_URL/projects/$project_id" | jq -r '.ssh_url_to_repo')
        success "Cloning project: $project_url"
        git clone "$project_url" && success "Project cloned successfully."
    else
        error "Invalid choice. Please try again."
    fi
}

# ================================
# Create a repository (project)
# ================================
create_repository() {
    local group_id="$1"
    read -rp "$(echo -e "${YELLOW}Enter project name: ${RESET}")" name
    read -rp "$(echo -e "${YELLOW}Enter project description: ${RESET}")" description
    read -rp "$(echo -e "${YELLOW}Enter project visibility (public, internal, private): ${RESET}")" visibility
    read -rp "$(echo -e "${YELLOW}Do you want to include a README.md file? (Y/N): ${RESET}")" include_readme
    include_readme=$( [[ "$include_readme" =~ ^[Yy]$ ]] && echo "true" || echo "false" )
    read -rp "$(echo -e "${YELLOW}Enable Auto DevOps for this repository? (Y/N): ${RESET}")" auto_devops
    auto_devops=$( [[ "$auto_devops" =~ ^[Yy]$ ]] && echo "true" || echo "false" )
    read -rp "$(echo -e "${YELLOW}Specify a CI/CD config path (leave empty for default): ${RESET}")" ci_config_path

    json_payload=$(cat <<EOF
{
  "name": "$name",
  "path": "$(echo "$name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')",
  "description": "$description",
  "visibility": "$visibility",
  "namespace_id": "$group_id",
  "initialize_with_readme": $include_readme,
  "auto_devops_enabled": $auto_devops,
  "ci_config_path": "$(echo "$ci_config_path" | jq -Rr @uri)"
}
EOF
)

    debug_log "Creating repository with payload: $json_payload"

    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                     --header "Content-Type: application/json" \
                     --data "$json_payload" \
                     "$GITLAB_API_URL/projects")
    debug_log "Raw API response for repository creation: $response"

    if echo "$response" | jq empty 2>/dev/null; then
        http_url=$(echo "$response" | jq -r '.http_url_to_repo')
        ssh_url=$(echo "$response" | jq -r '.ssh_url_to_repo')
        success "Repository '${name}' created successfully."
        echo -e "${GREEN}Clone using HTTPS:${RESET} git clone $http_url"
        echo -e "${GREEN}Clone using SSH:${RESET} git clone $ssh_url"
    else
        error "Failed to create repository. API response: $response"
    fi
}

# ================================
# Navigate through groups dynamically
# ================================
navigate_groups() {
    local current_group_id=""
    local current_group_name="Top-Level Groups"

    while true; do
        # Fetch subgroups or top-level groups
        if [[ -z "$current_group_id" ]]; then
            groups=$(fetch_groups)
        else
            groups=$(fetch_subgroups "$current_group_id")
        fi

        # Fetch projects for the current group
        local projects=$(fetch_projects "$current_group_id")

        echo -e "${MAGENTA}Available Groups and Projects in $current_group_name:${RESET}"

        # Display subgroups or a message if none exist
        if [[ -n "$groups" ]]; then
            mapfile -t group_array < <(echo "$groups")
            for i in "${!group_array[@]}"; do
                group_name=$(echo "${group_array[i]}" | cut -d ' ' -f2-)
                echo -e "${CYAN}$((i + 1)).${RESET} $group_name"
            done
        else
            echo -e "${YELLOW}No existing nested groups under this subgroup.${RESET}"
            group_array=()
        fi

        # Display projects in the current group
        if [[ -n "$projects" ]]; then
            echo -e "${CYAN}Projects:${RESET}"
            mapfile -t project_array < <(echo "$projects")
            for i in "${!project_array[@]}"; do
                project_name=$(echo "${project_array[i]}" | cut -d ' ' -f2-)
                echo -e "${CYAN}$(( ${#group_array[@]} + i + 1 )).${RESET} [Project] $project_name"
            done
        else
            project_array=()
        fi

        # Display options
        echo -e "${CYAN}$(( ${#group_array[@]} + ${#project_array[@]} + 1 )).${RESET} Clone or Create a Project"
        echo -e "${CYAN}$(( ${#group_array[@]} + ${#project_array[@]} + 2 )).${RESET} Create a Subgroup"
        echo -e "${CYAN}$(( ${#group_array[@]} + ${#project_array[@]} + 3 )).${RESET} Go Back"
        echo -e "${CYAN}$(( ${#group_array[@]} + ${#project_array[@]} + 4 )).${RESET} Cancel"

        # Read user input
        read -rp "$(echo -e "${YELLOW}Choose an option: ${RESET}")" choice

        # Handle project-related choices
        if (( choice > ${#group_array[@]} && choice <= ${#group_array[@]} + ${#project_array[@]} )); then
            local project_index=$(( choice - ${#group_array[@]} - 1 ))
            local selected_project="${project_array[$project_index]}"
            local project_name=$(echo "$selected_project" | cut -d ' ' -f2-)
            local project_id=$(echo "$selected_project" | cut -d ' ' -f1)

            echo -e "${CYAN}1.${RESET} Clone Project: $project_name"
            read -rp "$(echo -e "${YELLOW}Choose an option (1 to clone, 0 to cancel): ${RESET}")" action
            if [[ "$action" == "1" ]]; then
                project_url=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                                    "$GITLAB_API_URL/projects/$project_id" | jq -r '.ssh_url_to_repo')
                success "Cloning project: $project_url"
                git clone "$project_url" && success "Project cloned successfully."
            else
                info "Action canceled."
            fi
            continue
        fi

        # Handle group-related choices
        case $choice in
            $(( ${#group_array[@]} + ${#project_array[@]} + 1 )))
                if [[ -z "$projects" ]]; then
                    info "No projects to clone. Creating a new project instead."
                    create_repository "$current_group_id"
                else
                    echo -e "${CYAN}1.${RESET} Clone a Project"
                    echo -e "${CYAN}2.${RESET} Create a Project"
                    read -rp "$(echo -e "${YELLOW}Choose an option: ${RESET}")" sub_choice
                    case $sub_choice in
                        1) list_and_clone_project "$current_group_id" ;;
                        2) create_repository "$current_group_id" ;;
                        *) error "Invalid choice. Returning to menu." ;;
                    esac
                fi
                ;;
            $(( ${#group_array[@]} + ${#project_array[@]} + 2 )))
                create_subgroup "$current_group_id"
                ;;
            $(( ${#group_array[@]} + ${#project_array[@]} + 3 )))
                if [[ ${#group_stack[@]} -eq 0 ]]; then
                    warning "You are already at the top level."
                    continue
                fi
                state=$(pop_stack)
                current_group_id="${state%%:*}"
                current_group_name="${state##*:}"
                ;;
            $(( ${#group_array[@]} + ${#project_array[@]} + 4 )))
                success "Exiting."
                exit 0
                ;;
            *)
                if (( choice > 0 && choice <= ${#group_array[@]} )); then
                    selected_group="${group_array[choice - 1]}"
                    push_stack "$current_group_id" "$current_group_name"
                    current_group_id=$(echo "$selected_group" | cut -d ' ' -f1)
                    current_group_name=$(echo "$selected_group" | cut -d ' ' -f2-)
                else
                    error "Invalid choice. Please try again."
                fi
                ;;
        esac
    done
}

# ================================
# Push current group state onto the stack
# ================================
push_stack() {
    local group_id="$1"
    local group_name="$2"
    group_stack+=("$group_id:$group_name")
}

# ================================
# Pop the previous group state from the stack
# ================================
pop_stack() {
    if [[ ${#group_stack[@]} -gt 0 ]]; then
        local last_index=$(( ${#group_stack[@]} - 1 ))
        local state="${group_stack[last_index]}"
        unset group_stack[last_index]
        echo "$state"
    else
        echo ":Top-Level Groups"
    fi
}

# ================================
# Main Menu
# ================================
main_menu() {
    echo -e "${BOLD}${MAGENTA}GitLab Management Script${RESET}"
    echo -e "${CYAN}1.${RESET} List all Groups and Projects"
    echo -e "${CYAN}2.${RESET} Create a Subgroup"
    echo -e "${CYAN}3.${RESET} Clone or Create a Project"
    echo -e "${CYAN}4.${RESET} Cancel"

    read -rp "$(echo -e "${YELLOW}Choose an option: ${RESET}")" choice

    case $choice in
        1) list_all_groups_and_projects ;;
        2) navigate_groups ;;  # Subgroups are created within existing groups
        3) navigate_groups ;;  # Clone or create a project
        4) success "Exiting."; exit 0 ;;
        *) error "Invalid choice."; main_menu ;;
    esac
}

# ================================
# Execute Main Menu
# ================================
main_menu
	

