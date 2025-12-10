FROM php:8.3-fpm
WORKDIR /var/www/html
COPY ../../backend-laravel /var/www/html
RUN docker-php-ext-install pdo pdo_mysql
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=80"]
