#!/usr/bin/env bash

#Description
#Script for autodeploy projectX
#Deploy in:
#  - local (only project)
#  - test server with ssl
#  - test server no ssl
#  - production install

#Server requirements:
#  - OS: centOS

#Project server environment install:
#  - PostgreSQL
#  - Python and pip
#  - Django environment
#  - Project configuration
#  - nginx + ssl / nossl configuration
#  - gunicorn + configuretion


#----------------------------------------------------------------------------
#option parser

while [[ $# -gt 1 ]]
do
  key="$1"

  case $key in
    -t|--type)
    TYPE=$2
    shift ;;
    -s|--server)
    SERVER_NAME="$2"
    shift ;;
    -f|--frontend)
    FRONTEND="$2"
    shift ;;
    -p|--db-passwd)
    DB_PASSWD="$2"
    shift ;;
    -bb|--backend_branch)
    BACKEND_BRANCH="$2"
    shift ;;
    -fb|--frontend_branch)
    FRONTEND_BRANCH="$2"
    shift ;;
    -db|--database)
    DATABASE="$2"
    shift ;;
  esac

  shift
done


#----------------------------------------------------------------------------
#option validator
if [[ $TYPE = "prod" ]] || [[ $TYPE = "vm" ]] || [[ $TYPE = "dev" ]] || [[ $TYPE = "nossl" ]]; then
  if [ -z ${FRONTEND_BRANCH} ]; then
    echo "WARN: frontend release branch is missed!"
    echo "--> use master branch."
    FRONTEND_BRANCH="master"
  fi
  if [ -z ${BACKEND_BRANCH} ]; then
    echo "WARN: backend release branch is missed!"
    echo "--> use master branch."
    BACKEND_BRANCH="master"
  fi
  if [ -z ${FRONTEND} ]; then
    echo "ERROR: Frontend project not defined!"
    echo "--> use (-f | --frontend) option."
    exit
  fi
  if [[ $TYPE != "dev" ]] && [ -z ${SERVER_NAME} ]; then
    echo "ERROR: server hostname is missed."
    echo "--> use (-s | --server) option."
    exit
  fi
  if [[ $TYPE != "dev" ]] && [ -z ${DB_PASSWD} ]; then
    echo "ERROR: missed database password."
    echo "--> use (-p | --db_passwd option.)"
    exit
  fi
  if [[ $TYPE = "dev" ]] && [ -z ${DATABASE} ]; then
    echo "ERROR: missed database name."
    echo "--> use (-db | --database option.)"
    exit
  fi
else
  echo "ERROR: install type is missed!"
  echo "--> use (-t | --type) option."
  echo "--> argumets: prod, vm, dev, nossl."
  exit
fi


#----------------------------------------------------------------------------
#work environment

if [[ $TYPE != "dev" ]]; then

  #vim theme/settings
  wget -O ~/.vimrc http://dumpz.org/25712/nixtext/
  update-alternatives --set editor /usr/bin/vim.basic

  #create user
  useradd -m hotdog -s /bin/bash
  cp ~/.vimrc /home/hotdog
  mkdir /home/hotdog/.ssh
  ~/.ssh/authorized_keys
  chown -R hotdog:hotdog /home/hotdog
fi


#----------------------------------------------------------------------------
#packages install

if [[ $TYPE != "dev" ]]; then

  yes Y | yum install epel-release
  yes Y | yum update

  yes Y | yum install gcc
  yes Y | yum install systemd
  yes Y | yum install memcached

  yes Y | yum install postgresql-server
  yes Y | yum install postgresql-devel
  yes Y | yum install postgresql-contrib

  yes Y | yum -y install https://centos7.iuscommunity.org/ius-release.rpm
  yes Y | yum -y install python35u
  yes Y | yum -y install python35u-pip

  yum -y install nginx
fi


#----------------------------------------------------------------------------
#configure postgreSQL

if [[ $TYPE != "dev" ]]; then

  postgresql-setup initdb
  systemctl start postgresql

  sed -i "s/ident/md5/g" /var/lib/pgsql/data/pg_hba.conf

  systemctl restart postgresql
  systemctl enable postgresql

  sudo -u postgres psql postgres -c "CREATE DATABASE project_x;"
  sudo -u postgres psql postgres -c "CREATE USER ${FRONTEND} WITH PASSWORD '${DB_PASSWD}';"
  sudo -u postgres psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE project_x TO ${FRONTEND};"
fi


#----------------------------------------------------------------------------
#initialize django

if [[ $TYPE != "dev" ]]; then
  rm -rf /home/hotdog/projectX && mkdir /home/hotdog/projectX && cd "$_"
else
  rm -rf ../projectX && mkdir ../projectX && cd "$_"
fi

mkdir $PWD/venv_django
python3.5 -m venv $PWD/venv_django
source $PWD/venv_django/bin/activate

pip install django==1.9
pip install psycopg2==2.7.1
pip install django-ckeditor
pip install django-resized
pip install Pillow
pip install psycopg2
pip install gunicorn

pip3 install python3-memcached


#----------------------------------------------------------------------------
#configure project

mkdir $PWD/app_django
django-admin startproject configuration $PWD/app_django && cd "$_"

## NEED FIX
# Remove err: database connection isn't set to UTC
sed -i -e "s/USE_TZ = True/USE_TZ = False/g" ./configuration/settings.py >> /dev/null
sed -i -e "s/'UTC'/'Europe\/Moscow'/g" ./configuration/settings.py >> /dev/null
sed -i -e "s/'en-us'/'ru-ru'/g" ./configuration/settings.py        >> /dev/null
sed -i -e '55,70d' ./configuration/settings.py                     >> /dev/null
sed -i -e '57,68d' ./configuration/settings.py                     >> /dev/null
sed -i -e '93d'    ./configuration/settings.py                     >> /dev/null

if [[ $TYPE = "prod" ]]; then
  sed -i -e "s/DEBUG = True/DEBUG = False/g" ./configuration/settings.py >> /dev/null
  sed -i -e '28d' ./configuration/settings.py >> /dev/null
  cat >> ./configuration/settings.py << EOF
ALLOWED_HOSTS = ['${SERVER_NAME}', 'www.${SERVER_NAME}']
EOF
fi

if [[ $TYPE != "dev" ]]; then

  cat >> ./configuration/settings.py << EOF
DATABASES = {
  'default': {
    'ENGINE': 'django.db.backends.postgresql_psycopg2',
    'NAME': 'project_x',
    'USER': '${FRONTEND}',
    'PASSWORD': '${DB_PASSWD}',
    'HOST': 'localhost',
    'PORT': '',
  }
}
EOF

else
    cat >> ./configuration/settings.py << EOF
DATABASES = {
  'default': {
    'ENGINE': 'django.db.backends.postgresql_psycopg2',
    'NAME': '${DATABASE}',
    'USER': 'django',
    'PASSWORD': 'qwerty',
    'HOST': 'localhost',
    'PORT': '',
  }
}
EOF
fi

cat >> ./configuration/settings.py << EOF
INSTALLED_APPS = INSTALLED_APPS + [
  'django.contrib.sitemaps',
  'ckeditor_uploader',
  'ckeditor',
  'backend',
]

TEMPLATES = [
  {
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [os.path.join(BASE_DIR, 'frontend/templates/')],
    'APP_DIRS': True,
    'OPTIONS': {
      'context_processors': [
        'django.template.context_processors.debug',
        'django.template.context_processors.request',
        'django.contrib.auth.context_processors.auth',
        'django.contrib.messages.context_processors.messages',
      ],
    },
  },
]

DATE_FORMAT = 'd E Y в G:i'

CKEDITOR_UPLOAD_PATH = 'uploads/'
CKEDITOR_CONFIGS = {
  'default': {
    'removePlugins' : 'stylesheetparser',
    'allowedContent': True,
    'width': '100%',
    'toolbar_Full': [
       ['Styles', 'Format', 'Bold', 'Italic', 'Underline', 'Strike',
        'Subscript', 'Superscript', '-', 'RemoveFormat'],
       ['Image', 'Flash', 'Table', 'HorizontalRule'],
       ['TextColor', 'BGColor'],
       ['Smiley', 'sourcearea', 'SpecialChar'],
       ['Link', 'Unlink', 'Anchor'],
       ['NumberedList', 'BulletedList', '-', 'Outdent', 'Indent', '-',
        'Blockquote', 'CreateDiv', '-', 'JustifyLeft', 'JustifyCenter',
        'JustifyRight', 'JustifyBlock', '-', 'BidiLtr', 'BidiRtl'],
       ['Templates'],
       ['Cut', 'Copy', 'Paste', 'PasteText', 'PasteFromWord', '-',
        'Undo', 'Redo'],
       ['Find', 'Replace', '-', 'Scayt'],
       ['ShowBlocks'],
       ['Source', 'Templates'],
    ],
  }
}

CACHES = {
  'default': {
    'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
    'LOCATION': '127.0.0.1:11211',
  }
}

EOF

if [[ $TYPE != "dev" ]]; then
  cat >> ./configurations/settings.py << EOF
  STATIC_URL = '/static/'
  STATIC_ROOT = os.path.join(BASE_DIR, 'frontend/static')

  MEDIA_URL = '/media/'
  MEDIA_ROOT = os.path.join(BASE_DIR, '../../media')

EOF
else
  cat >> ./configurations/settings.py << EOF
  STATIC_URL = '/static/'
  STATICFILES_DIRS = (os.path.join(BASE_DIR, 'frontend/static/'),)

  MEDIA_URL = '/media/'
  MEDIA_ROOT = os.path.join(BASE_DIR, '../../media')

EOF
fi

rm -rf ./configuration/urls.py && touch ./configuration/urls.py
if [[ $TYPE != "dev" ]]; then
  cat >> ./configuration/urls.py << EOF
  # -*- coding: utf-8 -*-
  from django.contrib   import admin
  from django.conf.urls import url, include

  from django.contrib.sitemaps import views as xml_site
  from backend.services.sitemap.sitemap import PostSitemap, HomeSitemap, FlowSitemap
  sitemaps = {'articles': PostSitemap, 'home': HomeSitemap, 'flow': FlowSitemap}

  urlpatterns = [
    url(r"^kmizar-admin-panel/", admin.site.urls),
    url(r"^ckeditor/", include("ckeditor_uploader.urls")),
    url(r"", include("backend.urls")),
    url(r'^sitemap.xml$', xml_site.sitemap, {'sitemaps': sitemaps})
  ]

EOF
else
  cat >> ./configuration/urls.py << EOF
  # -*- coding: utf-8 -*-
  from django.contrib   import admin
  from django.conf.urls import url, include

  from django.conf.urls.static import static
  from django.conf import settings

  from django.contrib.sitemaps import views as xml_site
  from backend.services.sitemap.sitemap import PostSitemap, HomeSitemap, FlowSitemap
  sitemaps = {'articles': PostSitemap, 'home': HomeSitemap, 'flow': FlowSitemap}

  urlpatterns = [
    url(r"^kmizar-admin-panel/", admin.site.urls),
    url(r"^ckeditor/", include("ckeditor_uploader.urls")),
    url(r"", include("backend.urls")),
    url(r'^sitemap.xml$', xml_site.sitemap, {'sitemaps': sitemaps})
  ]

  urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

EOF
fi

rm -rf settings.py-e
mkdir -p ../../media/tag_group_icons ../../media/uploads


#----------------------------------------------------------------------------
#deploy frontend / backend

git clone -b ${BACKEND_BRANCH} git@github.com:kmizar/backend.git
git clone -b ${FRONTEND_BRANCH} git@github.com:kmizar/${FRONTEND}.git

if [[ $TYPE != "dev" ]]; then
  rm -rf ./backend/.git ./backend/README.md ./backend/.gitignore
  rm -rf ./${FRONTEND}/.git ./${FRONTEND}/README.md ./${FRONTEND}/.gitignore
fi

if [[ $TYPE = "dev" ]]; then
  sed -i "s/https/http:\/\/127.0.0.1/g" $PWD/backend/models.py
fi

if [[ $TYPE = "nossl" ]]; then
  sed -i "s/https/http:\/\/${SERVER_NAME}/g" $PWD/backend/models.py
fi

if [[ $TYPE = "prod" ]] || [[ $TYPE = "vm"  ]]; then
  sed -i "s/https/https:\/\/${SERVER_NAME}/g" $PWD/backend/models.py
  sed -i "19r ./${FRONTEND}/templates/yandex.txt" ./${FRONTEND}/templates/base.html
  rm -rf ./${FRONTEND}/templates/yandex.txt
fi

if [[ $TYPE = "prod" ]]; then
  sed -i -e "s/name='robots'/name='yandex-verification'/g" ./${FRONTEND}/templates/base.html >> /dev/null
  sed -i -e "s/content='noindex,nofollow'/content='e2ec3935ebde1b47'/g" ./${FRONTEND}/templates/base.html >> /dev/null
else
  rm -rf ./${FRONTEND}/static/robots.txt
  touch  ./${FRONTEND}/static/robots.txt
  cat >> ./${FRONTEND}/static/robots.txt << EOF
User-agent: *
Disallow: /
EOF
fi

mkdir ./backend/migrations && touch ./backend/migrations/__init__.py
mv ./${FRONTEND} ./frontend

python manage.py makemigrations
python manage.py migrate backend
python manage.py migrate

yes "yes" | python manage.py collectstatic


#----------------------------------------------------------------------------
#configure gunicorn daemon

if [[ $TYPE != "dev" ]]; then
  rm -rf /etc/systemd/system/gunicorn.service
  touch /etc/systemd/system/gunicorn.service
  cd ../

  chmod 0777 /etc/systemd/system/gunicorn.service
  cat >> /etc/systemd/system/gunicorn.service << EOF
[Unit]
Description=gunicorn daemon
After=network.target
[Service]
User=root
Group=root
WorkingDirectory=$PWD/app_django
ExecStart=$PWD/venv_django/bin/gunicorn --workers 1 --bind \
  unix:$PWD/app_django/projectX.sock configuration.wsgi:application
[Install]
WantedBy=multi-user.target

EOF

  sudo chmod 0644 /etc/systemd/system/gunicorn.service
  systemctl daemon-reload
  systemctl stop gunicorn
  systemctl start gunicorn
  systemctl enable gunicorn
fi


#----------------------------------------------------------------------------
#configure nginx

if [[ $TYPE != "dev" ]]; then
  rm -rf /etc/nginx/nginx.conf
  touch /etc/nginx/nginx.conf
  cd ../

  chmod 0777 /etc/nginx/nginx.conf
  cat >> /etc/nginx/nginx.conf << EOF
user root;
worker_processes 1;
error_log $PWD/projectX/logs_django/nginx/error.log warn;
events {
  worker_connections  1024;
}
http {
  server_names_hash_bucket_size 64;
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  log_format   main '\$remote_addr - \$remote_user [\$time_local] \$status '
    '"\$request" \$body_bytes_sent "\$http_referer" '
    '"\$http_user_agent" "\$http_x_forwarded_for"';
  access_log $PWD/projectX/logs_django/nginx/access.log main;

  sendfile off;
  keepalive_timeout  65;
  include /etc/nginx/conf.d/*.conf;
  client_max_body_size 10M;

  proxy_cache_path
    /home/hotdog/projectX/app_django/nginx_tmp/cache
    levels=1:2
    keys_zone=cache:480m
    max_size=1G;
  proxy_temp_path /home/hotdog/projectX/app_django/nginx_tmp/proxy 1 2;
  proxy_ignore_headers Expires Cache-Control;
  proxy_cache_use_stale error timeout invalid_header http_502;
  proxy_cache_bypass \$cookie_session \$http_x_update;
  proxy_no_cache \$cookie_session;

  gzip on;
  gzip_disable "msie6";
  gzip_comp_level 1;
  gzip_vary on;
  gzip_proxied any;
  gzip_buffers 16 8k;
  gzip_http_version 1.1;
  gzip_static on;
  gzip_types
    text/plain
    text/css
    application/json
    application/x-javascript
    text/xml application/xml
    application/xml+rss
    text/javascript
    application/javascript;

EOF
fi


if [[ $TYPE = "prod" ]] || [[ $TYPE = "vm"  ]]; then
  cat >> /etc/nginx/nginx.conf << EOF
  server {
    server_name ${SERVER_NAME}, www.${SERVER_NAME};
    listen 80;
    return 301 https://${SERVER_NAME}\$request_uri;
  }

  server {
    listen 443 ssl http2;
    server_name ${SERVER_NAME}, www.${SERVER_NAME};

    if (\$host ~* www\.(.*)) {
      set \$host_without_www \$1;
      rewrite ^(.*)\$ http://\$host_without_www\$1 permanent;
    }

    ssl on;
    ssl_stapling on;
    ssl_prefer_server_ciphers on;

    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    ssl_certificate $PWD/ssl_certificate/chain.crt;
    ssl_certificate_key $PWD/ssl_certificate/private.key;
    ssl_dhparam $PWD/ssl_certificate/dhparam.pem;

    ssl_session_timeout 24h;
    ssl_session_cache shared:SSL:2m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers kEECDH+AES128:kEECDH:kEDH:-3DES:kRSA+AES128:kEDH+3DES:DES-CBC3-SHA:!RC4:!aNULL:!eNULL:!MD5:!EXPORT:!LOW:!SEED:!CAMELLIA:!IDEA:!PSK:!SRP:!SSLv2;
    add_header Content-Security-Policy-Report-Only "default-src https:; script-src https: 'unsafe-eval' 'unsafe-inline'; style-src https: 'unsafe-inline'; img-src https: data:; font-src https: data:; report-uri /csp-report";
    add_header Strict-Transport-Security "max-age=31536000;";

EOF
fi
if [[ $TYPE = "nossl" ]]; then
  cat >> /etc/nginx/nginx.conf << EOF
  server {
    listen 80;
    server_name ${SERVER_NAME};

EOF
fi
if [[ $TYPE != "dev" ]]; then
  cat >> /etc/nginx/nginx.conf << EOF
    location /robots.txt {
      root $PWD/projectX/app_django/frontend/static;
    }

    location /static {
      root $PWD/projectX/app_django/frontend;
      add_header Cache-Control private;
      expires 360d;
    }

    location /media {
      root $PWD;
      add_header Cache-Control public;
      expires 360d;
    }

    error_page 404 /404.html;
    location = /404.html {
      root $PWD/projectX/app_django/frontend/templates;
      internal;
    }

    location / {
      proxy_cache cache;
      proxy_cache_valid 480m;
      proxy_cache_valid 404 10m;
      proxy_set_header Host \$http_host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_pass http://unix:$PWD/projectX/app_django/projectX.sock;
    }
  }
}

EOF
fi

if [[ $TYPE != "dev" ]]; then
  mkdir $PWD/ssl_certificate
  mkdir -p $PWD/projectX/app_django/nginx_tmp/proxy
  mkdir -p $PWD/projectX/app_django/nginx_tmp/cache
  mkdir -p $PWD/projectX/logs_django/nginx

  chmod 0644 /etc/nginx/nginx.conf
  chmod 700 $PWD/projectX/app_django/nginx_tmp/proxy
  chmod 700 $PWD/projectX/app_django/nginx_tmp/cache

  sudo usermod -a -G hotdog nginx
  find $PWD/projectX/app_django/frontend/static/css -name \*.* -exec gzip -9 {} \;
  find $PWD/projectX/app_django/frontend/static/js -name \*.* -exec gzip -9 {} \;

  iptables -I INPUT 4 -p tcp --dport 80 -j ACCEPT
  iptables -I INPUT 4 -p tcp --dport 443 -j ACCEPT

  fuser -k 80/tcp

  service nginx restart
  systemctl enable nginx
fi
