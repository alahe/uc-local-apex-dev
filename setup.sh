#!/bin/bash
PRINT_RED='\033[0;31m'
PRINT_RESET='\033[0m'

IMAGE_SOURCE="${IMAGE_SOURCE:-oracle}"
DB_IMAGE_REPO="container-registry.oracle.com"
ORDS_IMAGE_REPO="container-registry.oracle.com"

case "$IMAGE_SOURCE" in
  oracle)
    ;;
  company)
    source ./scripts/util/load_company_registry.sh
    if ! load_company_registry_conf; then
      exit 1
    fi
    DB_IMAGE_REPO="$COMPANY_IMAGE_REPO"
    ORDS_IMAGE_REPO="$COMPANY_IMAGE_REPO"
    ;;
  *)
    echo -e "${PRINT_RED}Invalid IMAGE_SOURCE '$IMAGE_SOURCE'. Use 'oracle' or 'company'.${PRINT_RESET}"
    exit 1
    ;;
esac

source ./scripts/util/generate_password.sh

# generate sys password
SYS_PASSWORD=$(generate_password)

# if .env exsits, rename to .env.bak
if [ -f .env ]; then
  mv .env .env.bak
fi

# write .env file with passwords
echo "ORACLE_PASSWORD=\"$SYS_PASSWORD\"" >.env
echo "ORACLE_PWD=\"$SYS_PASSWORD\"" >>.env
#echo "APP_USER=\"$APP_USER\"" >>.env
#echo "APP_USER_PASSWORD=\"$APP_USER_PASSWORD\"" >>.env
echo "DB_CONN_BASE=local-26ai" >>.env
echo "DB_CONN_NAME=local-26ai-sys" >>.env
echo "CONTAINER_NAME=local-26ai" >>.env
echo "DBSERVICENAME=\"FREEPDB1\"" >>.env
echo "DBHOST=\"26ai\"" >>.env
echo "DBPORT=\"1521\"" >>.env
echo "FORCE_SECURE=\"false\"" >>.env
echo "IMAGE_SOURCE=\"$IMAGE_SOURCE\"" >>.env
echo "DB_IMAGE_REPO=\"$DB_IMAGE_REPO\"" >>.env
echo "ORDS_IMAGE_REPO=\"$ORDS_IMAGE_REPO\"" >>.env

# Optional internal mirror for APEX install/patch files, so developers don't
# have to download apex-latest.zip / patch bundles themselves. Leave empty to
# keep the default behavior (download from Oracle / My Oracle Support, or
# use a manually pre-staged ./apex-latest.zip / apex-patches/*.zip). Fill
# these in once the files are uploaded to the internal artifact repository —
# see scripts/upgrade-apex.sh and scripts/apply-patches.sh for details.
echo "APEX_MIRROR_URL=\"\"" >>.env
echo "APEX_PATCHES_MIRROR_URL=\"\"" >>.env
echo "APEX_PATCHES_MANIFEST=\"\"" >>.env


echo "Created .env file"

# create ords-config directory if not exists
if [ ! -d ./ords-config ]; then
  mkdir ./ords-config
  chmod 777 ./ords-config
fi

mkdir -p ./backups/export
mkdir -p ./backups/import
