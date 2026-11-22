# ⚠️ Ten Dockerfile DZIAŁA, ale jest pełen typowych grzechów.
# Twoje zadanie: odchudzić go i przyspieszyć build (README, kroki 1-8).

FROM php:8.3-apache

RUN apt-get update
RUN apt-get install -y git unzip libzip-dev libicu-dev libpng-dev vim curl wget
RUN docker-php-ext-install zip intl gd pcntl
RUN pecl install xdebug && docker-php-ext-enable xdebug

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /var/www/html
COPY . .
RUN composer install

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/*.conf

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["web"]
