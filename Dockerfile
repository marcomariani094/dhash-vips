FROM ruby:2.5-alpine3.7

ARG VIPS_VERSION=8.9.0
ARG DHASH_VIPS_VERSION

RUN gem install dhash-vips -v $GEM_VERSION

