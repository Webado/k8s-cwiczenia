# syntax=docker/dockerfile:1
# ============================================================================
# ROZWIĄZANIE: wielostopniowy (multi-stage) Dockerfile z targetami dev i prod
#
#   docker build --target prod   -t sklep:prod   .
#   docker build --target worker -t sklep:worker .
#   docker build --target dev    -t sklep:dev    .
# ============================================================================

# ---------- base: wspólna podstawa (to, czego potrzebuje KAŻDE środowisko) ----------
FROM php:8.3-apache AS base

# install-php-extensions sam doinstaluje biblioteki potrzebne do kompilacji
# i USUNIE je po kompilacji (zostają tylko biblioteki runtime). Zamiast 4 warstw z apt -> 1 warstwa.
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions intl zip gd pcntl opcache

RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/*.conf

WORKDIR /var/www/html

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["web"]


# ---------- vendor: instalacja zależności (etap pomocniczy, NIE trafia na produkcję) ----------
FROM base AS vendor

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_CACHE_DIR=/tmp/composer-cache

# 1) NAJPIERW tylko pliki zależności. Ta warstwa (i composer install) przebuduje się
#    TYLKO gdy zmieni się composer.json/lock, a nie przy każdej zmianie w kodzie.
COPY composer.json composer.lock ./

# 2) Cache mount: pobrane paczki zostają między buildami (nie trafiają do obrazu)
RUN --mount=type=cache,target=/tmp/composer-cache \
    composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

# 3) DOPIERO TERAZ kod (zmienia się często, więc na końcu)
COPY . .
RUN composer dump-autoload --no-dev --classmap-authoritative


# ---------- dev: lokalne środowisko (xdebug, composer, kod montowany z dysku) ----------
FROM base AS dev

RUN install-php-extensions xdebug
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
# Kodu NIE kopiujemy: w docker-compose montujemy go jako volume (zmiany widać bez rebuilda)


# ---------- prod: to, co trafia na Kubernetes ----------
FROM base AS prod

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
 && { \
      echo 'opcache.enable=1'; \
      echo 'opcache.validate_timestamps=0'; \
      echo 'opcache.memory_consumption=128'; \
      echo 'opcache.max_accelerated_files=20000'; \
    } > "$PHP_INI_DIR/conf.d/zz-opcache-prod.ini"

# Z etapu vendor bierzemy TYLKO gotowy katalog aplikacji: bez composera, bez cache, bez paczek dev
COPY --from=vendor --chown=www-data:www-data /var/www/html /var/www/html


# ---------- worker: ten sam kod, ale konsument kolejki zamiast Apache'a ----------
FROM prod AS worker

# PUŁAPKA: obraz php:*-apache ma "STOPSIGNAL SIGWINCH" (łagodne zatrzymanie Apache'a).
# Worker by go odziedziczył: docker stop / Kubernetes wysłałby SIGWINCH, handler SIGTERM w PHP
# nigdy by się nie odpalił, a po timeoucie proces dostałby SIGKILL (exit 137).
STOPSIGNAL SIGTERM
CMD ["worker"]
