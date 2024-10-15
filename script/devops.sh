#!/usr/bin/env bash
#########################################################################
# Onboard and manage application on cloud infrastructure.
# Usage: devops.sh [COMMAND]
# Globals:
#   ENV_FILE        Path to the environment variables file.
# Commands
#   provision  Provision resources.
#   deploy          Prepare the app and deploy to cloud.
# Params
#    -e, --env      Environment name (dev, prod, etc.)
#    -h, --help     Show this message and get help for a command.
#    -l, --location Resource location. Default westus3
#########################################################################

# Stop on errors
set -e

show_help() {
    echo "$0 : Onboard and manage application on cloud infrastructure." >&2
    echo "Usage: devops.sh [COMMAND]"
    echo "Globals"
    echo
    echo "Commands"
    echo "  provision       Provision resources."
    echo "  deploy          Prepare the app and deploy to cloud."
    echo "Params"
    echo "   -e, --env      Environment name (dev, prod, etc.)"
    echo "   -h, --help     Show this message and get help for a command."
    echo "   -l, --location Resource location. Default westus3"
    echo
}

validate_parameters(){
    # Check command
    if [ -z "$1" ]
    then
        echo "COMMAND is required (provision | deploy)" >&2
        show_help
        exit 1
    fi
}

replace_parameters(){
    # Replace parameters with environment variables or inline variables
    additional_parameters=()
    if [ -n "$location" ]
    then
        additional_parameters+=("location=$location")
    fi

    if [ -n "$environment" ]
    then
        additional_parameters+=("environmentName=$environment")
    fi

    if [ -n "$COMMON_RESOURCE_GROUP" ]
    then
        additional_parameters+=("commonResourceGroupName=$COMMON_RESOURCE_GROUP")
    fi

    if [ -n "$COMMON_KEY_VAULT_NAME" ]
    then
        additional_parameters+=("keyVaultName=$COMMON_KEY_VAULT_NAME")
    fi

    if [ -n "$COMMON_APP_SERVICE_PLAN_NAME" ]
    then
        additional_parameters+=("appServicePlanName=$COMMON_APP_SERVICE_PLAN_NAME")
    fi

    if [ -n "$COMMON_APP_INSIGHTS_NAME" ]
    then
        additional_parameters+=("applicationInsightsName=$COMMON_APP_INSIGHTS_NAME")
    fi

    if [ -n "$COMMON_LOG_ANALYTICS_NAME" ]
    then
        additional_parameters+=("logAnalyticsName=$COMMON_LOG_ANALYTICS_NAME")
    fi

    echo "${additional_parameters[@]}"

}

validate_deployment(){
    local location="$1"
    local environment="$2"
    local deployment_name="FullStackReactApp.Provisioning-${run_date}"

    IFS=' ' read -ra additional_parameters <<< "$(replace_parameters)"
    # additional_parameters=($(replace_parameters))

    echo "Validating ${deployment_name} with ${additional_parameters[*]}"

    result=$(az deployment sub validate \
        --name "${deployment_name}" \
        --location "$location" \
        --template-file "${INFRA_DIRECTORY}/main.bicep" \
        --parameters "${INFRA_DIRECTORY}/main.parameters.json" \
        --parameters "${additional_parameters[@]}")

    state=$(echo "$result" | jq -r '.properties.provisioningState')
    if [ "$state" != "Succeeded" ]
    then
        echo "Validation failed with state $state"
        echo "$result" | jq -r '.properties.error.details[]'
        exit 1
    fi

}

provision(){
    # Provision resources for the application.
    local location="$1"
    local environment="$2"
    local deployment_name="FullStackReactApp.Provisioning-${run_date}"

    IFS=' ' read -ra additional_parameters <<< "$(replace_parameters)"

    echo "Deploying ${deployment_name} with ${additional_parameters[*]}"

    # shellcheck source=/workspaces/trykle-web/iac/main.sh
    # source "${INFRA_DIRECTORY}/main.sh" --parameters "${additional_parameters[@]}"

    result=$(az deployment sub create \
        --name "${deployment_name}" \
        --location "$location" \
        --template-file "${INFRA_DIRECTORY}/main.bicep" \
        --parameters "${INFRA_DIRECTORY}/main.parameters.json" \
        --parameters "${additional_parameters[@]}")

    echo "$result" >> "${PROJ_ROOT_PATH}/.azuredeploy.log"

    state=$(echo "$result" | jq -r '.properties.provisioningState')
    if [ "$state" != "Succeeded" ]
    then
        echo "Deployment failed with state $state"
        echo "$result" | jq -r '.properties.error.details[]'
        exit 1
    fi

    # Get the output variables from the deployment
    output_variables=$(az deployment sub show -n "${deployment_name}" --query 'properties.outputs' --output json)
    echo "Save deployment $deployment_name output variables to ${ENV_FILE}"
    {
        echo ""
        echo "# Deployment output variables"
        echo "# Generated on ${ISO_DATE_UTC}"
        echo "$output_variables" | jq -r 'to_entries[] | "\(.key | ascii_upcase )=\(.value.value)"'
    }>> "$ENV_FILE"
}

delete(){
    echo pass
}

deploy(){

    temp_build_dir="./.deploy"
    archive_name="web_app_archive-${run_date}"

    if [[ -z "$WEB_APP_NAME" ]]; then
        echo 'WEB_APP_NAME is required' >&2
        show_help
        exit 2
    fi

    if [[ -z "$WEB_APP_RESOURCE_GROUP_NAME" ]]; then
        echo 'WEB_APP_RESOURCE_GROUP_NAME is required' >&2
        show_help
        exit 2
    fi

    # Remove previous archive
    echo "Remove previous zip if exists."
    if  ls ./*.zip 1> /dev/null 2>&1; then
        echo "Deleting existing .zip files."
        rm ./*.zip
    fi

    echo "Check if dir exists ${temp_build_dir}"
    if [ ! -d "$temp_build_dir" ]; then
        echo "Directory does not exist. $temp_build_dir. Creating ..."
        mkdir "$temp_build_dir"
    else
        echo "Deleting existing ./${temp_build_dir}"
        rm -rf ./"${temp_build_dir:?}"
        mkdir "$temp_build_dir"
    fi

    # copy files to deploy dir
    echo "Copying files to deploy dir"
    cp -r ./static "${temp_build_dir}"
    cp -r ./templates "${temp_build_dir}"
    cp -r ./app.py "${temp_build_dir}"
    cp -r ./requirements.txt "${temp_build_dir}"

    # Change to the target directory
    cd "${temp_build_dir}" || exit 1

    echo "Creating zip"

    py_exclude=('*.pyc' '*__pycache__*')
    flask_exclude=('*flask_session*')
    # zip -r "$archive_name" . -x "${dir_exclude[@]}" "${files_exclude[@]}" "${py_exclude[@]}" "${py_exclude[@]}" "${flask_exclude[@]}"
    zip -r "$archive_name" . -x "${py_exclude[@]}" "${py_exclude[@]}" "${flask_exclude[@]}"

    echo Initiate deployment
    az webapp deploy --name "${WEB_APP_NAME}" --resource-group "$WEB_APP_RESOURCE_GROUP_NAME" --type zip --src-path "${archive_name}.zip"

}

update_environment_variables(){
    echo pass
}

# Globals
PROJ_ROOT_PATH=$(cd "$(dirname "$0")"/..; pwd)
echo "Project root: $PROJ_ROOT_PATH"
ENV_FILE="${PROJ_ROOT_PATH}/.env"
INFRA_DIRECTORY="${PROJ_ROOT_PATH}/iac"

# Argument/Options
LONGOPTS=env:,resource-group:,location:,jumpbox,help
OPTIONS=e:g:l:jh

# Variables
environment="dev"
location="westus3"
run_date=$(date +%Y%m%dT%H%M%S)
# ISO_DATE_UTC=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Parse arguments
TEMP=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$TEMP"
unset TEMP
while true; do
    case "$1" in
        -e|--env)
            environment="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit
            ;;
        -l|--location)
            location="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown parameters."
            show_help
            exit 1
            ;;
    esac
done

validate_parameters "$@"
command=$1
case "$command" in
    create_sp)
        create_sp
        exit 0
        ;;
    provision)
        validate_deployment "$location" "$environment"
        provision "$location" "$environment"
        exit 0
        ;;
    delete)
        delete
        exit 0
        ;;
    deploy)
        deploy
        exit 0
        ;;
    update_env)
        update_environment_variables
        exit 0
        ;;
    *)
        echo "Unknown command."
        show_help
        exit 1
        ;;
esac
