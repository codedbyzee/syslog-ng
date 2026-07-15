FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    syslog-ng \
    syslog-ng-mod-rdkafka \
    librdkafka1 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY config/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf

EXPOSE 514/udp 514/tcp

CMD ["syslog-ng", "-F"]
