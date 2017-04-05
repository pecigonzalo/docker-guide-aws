FROM debian:8
MAINTAINER Gonzalo Peci <pecigonzalo@outlook.com>
ENV DEBIAN_FRONTEND noninteractive


RUN apt-get update && \
  apt-get install -y \
    jq \
    libltdl-dev \
    python-pip \
    cron \
    wget && \
  pip install -U pip && \
  pip install awscli

WORKDIR /

COPY ./crontabs/root /usr/docker/crontab.txt

RUN /bin/sh -c /usr/bin/crontab /usr/docker/crontab.txt

COPY ./bin/* /usr/bin/
COPY entry.sh /

CMD ["/entry.sh"]