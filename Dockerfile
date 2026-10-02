FROM php:7.4-apache

# Debian bullseye is end-of-life: its security repo index still lists updates
# whose packages are gone (404), so install from the main repo only.
RUN sed -i '/bullseye-security/d' /etc/apt/sources.list
RUN apt update
RUN apt install -y \
  default-mysql-client \
  postgresql-client \
  libpq-dev \
  zlib1g-dev \
  libpng-dev \
  libjpeg-dev \
  libfreetype-dev
RUN docker-php-ext-install mysqli && \
  docker-php-ext-enable mysqli && \
  docker-php-ext-install pgsql pdo_pgsql && \
  docker-php-ext-configure gd --with-freetype --with-jpeg && \
  docker-php-ext-install gd
RUN apt clean

WORKDIR /var/www/html

COPY . .
COPY ./docker/php.ini-production /usr/local/etc/php/conf.d/php.ini

RUN  chown -R www-data:www-data /var/www/html/gui/templates_c

# Log and upload folders live on volumes; a fresh named volume copies this
# ownership, so the web server (www-data) can write to them.
RUN mkdir -p /var/testlink/logs /var/testlink/upload_area && \
  chown -R www-data:www-data /var/testlink
