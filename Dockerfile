FROM debian:stretch-slim
MAINTAINER Gonzalo Peci <pecigonzalo@outlook.com>
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
  apt-get install --no-install-recommends -y \
    jq \
    libltdl-dev \
    python-setuptools \
    python-pip \
    cron \
    wget && \
  rm -rf /var/lib/apt/lists/* && \
  apt-get clean

RUN pip install -U pip && \
  pip install awscli

WORKDIR /

RUN mkdir -p /usr/docker /var/log/cron

COPY ./bin/* /usr/bin/
COPY ./crontabs/root /usr/docker/crontab.txt

COPY entry.sh /

CMD ["/entry.sh"]
