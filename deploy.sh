#!/usr/bin/env bash

# Define variables to determine if the application has to be put down. In case of a hotfix, it's possible to run this
# script with ./deploy.sh APP_DOWN=false MIGRATE_DATABASE=false to enable a quick fix.
APP_DOWN=true
MIGRATE_DATABASE=true

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            APP_DOWN)           APP_DOWN=${VALUE} ;;
            MIGRATE_DATABASE)   MIGRATE_DATABASE=${VALUE} ;;
            *)
    esac
done

if [ ${MIGRATE_DATABASE} == "true" ] || [ ${APP_DOWN} == "true" ] ; then
    echo "Updating app with downtime"
else
    echo "Updating app without downtime"
fi

echo "Press Ctrl+C to cancel or wait 10 seconds to proceed"

sleep 10;

# To prevent leaking development credentials to the end user
php artisan clear
php artisan cache:clear
php artisan config:clear

# Run yarn locally
yarn install
yarn run production
yarn run admin-production

# Update the application code
rsync -avx app/ evdweel@van-der-weel.nl:app/ --delete
rsync -avx bootstrap/ evdweel@van-der-weel.nl:bootstrap/ --delete
rsync -avx config/ evdweel@van-der-weel.nl:config/ --delete
rsync -avx database/ evdweel@van-der-weel.nl:database/ --delete
rsync -avx resources/ evdweel@van-der-weel.nl:resources/ --delete
rsync -avx routes/ evdweel@van-der-weel.nl:routes/ --delete
rsync -avx public/assets/ evdweel@van-der-weel.nl:public/assets/ --delete

scp composer.lock evdweel@van-der-weel.nl:composer.lock
scp composer.json evdweel@van-der-weel.nl:composer.json

scp public/mix-manifest.json evdweel@van-der-weel.nl:public/mix-manifest.json

# If the application needs to put down, do so. This is always done when a database migration is needed
if [ ${MIGRATE_DATABASE} == "true" ] || [ ${APP_DOWN} == "true" ] ; then
    ssh evdweel@van-der-weel.nl 'php artisan down'
fi

# The config has to be cached before installing the composer dependencies.
ssh evdweel@van-der-weel.nl 'php artisan config:cache'
ssh evdweel@van-der-weel.nl 'composer install'

# Migrate the datbase
if [ ${MIGRATE_DATABASE} == "true" ] ; then
    ssh evdweel@van-der-weel.nl 'php artisan migrate --force'
fi

# Make the application available
if [ ${MIGRATE_DATABASE} == "true" ] || [ ${APP_DOWN} == "true" ] ; then
    ssh evdweel@van-der-weel.nl 'php artisan up'
fi

ssh evdweel@van-der-weel.nl 'php artisan queue:restart'