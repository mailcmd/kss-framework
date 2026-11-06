#!/bin/bash
test ! -d lib && echo "ERROR: You can not run this script from other directory than project root!!!" && exit 1

test -f lib/server/kss_webserver.ex && echo "WARNING: setup skipped!" && exit 0

test -f priv/kss.installed && echo "WARNING: KSS already installed!" && exit 0

echo "Running KSS setup..."

mkdir lib/layout 
cp -R deps/kss/lib/layout/* lib/layout/

mkdir -p config/local
cp -R deps/kss/config/config.exs config/config.exs
cp -R deps/kss/config/local.config.exs.example config/local/config.exs

mkdir -p priv/www/imgs
mkdir priv/www/css
mkdir priv/www/js

touch priv/www/main.html

deps/kss/scripts/update_kssjs.sh

touch priv/kss.installed

exit 0

