#!/usr/bin/env bash
######################################################
# Create a cloud CICD system identity to authenticate
# using OpenId Connect (OIDC) federated credentials.
# Sets CICD_CLIENT_ID in .env
# Globals:
#   CICD_CLIENT_NAME
#   AZURE_TENANT_ID
#   AZURE_SUBSCRIPTION_ID
#   GITHUB_ORG
#   GITHUB_REPO
# Params
#    -h, --help             Show this message and get help for a command.
######################################################

# Stop on errors
set -e

show_help() {
    echo "$0 : Create a cloud CICD system identity to authenticate using OpenId Connect (OIDC) federated credentials." >&2
    echo "Usage: create_cicd_sp.sh [OPTIONS]" >&2
    echo "Sets CICD_CLIENT_ID in .env" >&2
    echo "Globals"
    echo "   CICD_CLIENT_NAME"
    echo "   AZURE_TENANT_ID"
    echo "   AZURE_SUBSCRIPTION_ID"
    echo "   GITHUB_ORG"
    echo "   GITHUB_REPO"
    echo
    echo "Arguments"
    echo "   -h, --help             Show this message and get help for a command."
    echo
}

validate_parameters(){

    # Check CICD_CLIENT_NAME
    if [ -z "$CICD_CLIENT_NAME" ]
    then
        echo "CICD_CLIENT_NAME is required" >&2
        show_help
        exit 1
    fi

    # Check GITHUB_ORG
    if [ -z "$GITHUB_ORG" ]
    then
        echo "GITHUB_ORG is required" >&2
        show_help
        exit 1
    fi

    # Check GITHUB_REPO
    if [ -z "$GITHUB_REPO" ]
    then
        echo "GITHUB_REPO is required" >&2
        show_help
        exit 1
    fi

    # Check AZURE_TENANT_ID
    if [ -z "$AZURE_TENANT_ID" ]
    then
        echo "AZURE_TENANT_ID is required" >&2
        show_help
        exit 1
    fi

    # Check AZURE_SUBSCRIPTION_ID
    if [ -z "$AZURE_SUBSCRIPTION_ID" ]
    then
        echo "AZURE_SUBSCRIPTION_ID is required" >&2
        show_help
        exit 1
    fi

}

create_sp(){

    # Constants
    # ms_graph_api_id="00000003-0000-0000-c000-000000000000"
    # ms_graph_user_invite_all_permission="09850681-111b-4a89-9bed-3f2cae46d706"
    # ms_graph_user_read_write_all_permission="741f803b-c850-494e-b5df-cde7c675a1ca"
    # ms_graph_directory_read_write_all_permission="19dbc75e-c2e2-444c-a770-ec69d8559fc7"

    # App Names
    app_name="${CICD_CLIENT_NAME}_service_app"
    app_secret_name="${CICD_CLIENT_NAME}_client_secret"

    # az login --tenant "$AZURE_TENANT_ID"

    # Create an Azure Active Directory application and a service principal.
    az_ad_app_list_response=$(az ad app list --display-name "$app_name")
    app_client_id=$(jq -r '.[].appId' <<< "$az_ad_app_list_response")
    # app_client_id=$(az ad app list --display-name "$app_name" --query [].appId -o tsv)
    if [ -n "$app_client_id" ]
    then
        echo "Application already exists"
        app_id=$(jq -r '.[].id' <<< "$az_ad_app_list_response")
    else
        echo "Creating application"
        app_id=$(az ad app create --display-name "$app_name" --query id -o tsv)
        app_client_id=$(az ad app list --display-name "$app_name" --query [].appId -o tsv)
    fi

    # Create a service principal for the Azure Active Directory application.
    app_sp_id=$(az ad sp list --all --display-name "$app_name" --query "[].id" -o tsv)
    if [ -n "$app_sp_id" ]
    then
        echo "Service principal already exists"
    else
        echo "Creating service principal"
        az ad sp create --id "$app_id"
        app_sp_id=$(az ad sp list --all --display-name "$app_name" --query "[].id" -o tsv)
    fi

    # Assign contributor role to the app service principal
    if az role assignment list --assignee "$app_sp_id" --role contributor --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID" --query [].roleDefinitionName -o tsv | grep -q "Contributor"
    then
        echo "Service principal already has the contributor role"
    else
        echo "Assigning contributor role to the service principal"
        az role assignment create --assignee "$app_sp_id" --role contributor --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
        az role assignment create --role contributor --subscription "$AZURE_SUBSCRIPTION_ID" --assignee-object-id  "$app_sp_id" --assignee-principal-type ServicePrincipal --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
    fi

    # Add OIDC federated credentials for the application.
    az_ad_app_federated_credental_list_response=$(az rest --method GET --uri "https://graph.microsoft.com/beta/applications/$app_id/federatedIdentityCredentials")
    if [ "$(jq -r '.value[0].name' <<< "$az_ad_app_federated_credental_list_response")" == "$app_secret_name" ];
    then
        echo "OIDC federated credentials already exist"
    else
        echo "Creating OIDC federated credentials"
        post_body="{\"name\":\"$app_secret_name\","
        post_body=$post_body'"issuer":"https://token.actions.githubusercontent.com",'
        post_body=$post_body"\"subject\":\"repo:$GITHUB_ORG/$GITHUB_REPO:pull_request\","
        post_body=$post_body'"description":"GitHub CICD Service","audiences":["api://AzureADTokenExchange"]}'
        az rest --method POST --uri "https://graph.microsoft.com/beta/applications/$app_id/federatedIdentityCredentials" --body "$post_body"
    fi

    # Save variables to .env
    echo "Save Azure variables to ${ENV_FILE}"
    {
        echo ""
        echo "# Script create_cicd_sp.sh output variables create_sp"
        echo "# Generated on ${iso_date_utc}"
        echo "CICD_CLIENT_ID=$app_client_id"
    }>> "$ENV_FILE"

}

# Argument/Options
LONGOPTS=help
OPTIONS=h

## Globals
PROJ_ROOT_PATH=$(cd "$(dirname "$0")"/..; pwd)
ENV_FILE="${PROJ_ROOT_PATH}/.env"
iso_date_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Parse arguments
TEMP=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$TEMP"
unset TEMP
while true; do
    case "$1" in
        -h|--help)
            show_help
            exit
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

create_sp
