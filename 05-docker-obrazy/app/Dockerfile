# ⚠️ Ten Dockerfile DZIAŁA, ale jest pełen typowych grzechów.
# Twoje zadanie: odchudzić go i przyspieszyć build (README, kroki 1-8).

FROM php:8.3-apache AS base

COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions intl zip gd pcntl

RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/*.conf

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["web"]

#----------------
FROM base AS vendor

WORKDIR /var/www/html

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY . .

RUN composer dump-autoload

#----------------
FROM base AS dev

RUN install-php-extensions xdebug
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

#----------------
FROM base AS prod

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY --from=vendor --chown=www-data:www-data /var/www/html /var/www/html

#----------------
FROM prod AS worker

STOPSIGNAL SIGTERM
CMD ["worker"]