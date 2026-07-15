FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    syslog-ng \
    syslog-ng-mod-rdkafka \
    librdkafka1 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY config/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf
COPY config/tls/ /etc/syslog-ng/config/tls/

EXPOSE 514/udp 514/tcp 6514

CMD ["syslog-ng", "-F"]
