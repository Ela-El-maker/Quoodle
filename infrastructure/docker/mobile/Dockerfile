FROM ghcr.io/cirruslabs/flutter:3.22.0
WORKDIR /app
COPY ../../mobile-app /app
RUN flutter pub get
CMD ["flutter", "test"]
