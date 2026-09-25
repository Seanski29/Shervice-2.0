FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y curl git unzip ca-certificates
RUN git clone https://github.com/flutter/flutter.git -b 3.47.5 /flutter
ENV PATH="/flutter/bin:${PATH}"
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web --release --tree-shake-icons --pwa-strategy=none

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
