FROM ruby:2-alpine as builder

RUN apk add --update --virtual --upgrade \
  build-base \
  git wget curl inotify-tools \
  libxslt-dev \
  && rm -rf /var/cache/apk/*

ENV RAILS_VERSION 5.1.4
ENV RAILS_ENV production

RUN gem install -N bundler

RUN gem install -N nokogiri -- --use-system-libraries && \
  gem install -N rails --version "$RAILS_VERSION" && \
  echo 'gem: --no-document' >> ~/.gemrc && \
  cp ~/.gemrc /etc/gemrc && \
  chmod uog+r /etc/gemrc && \
  # cleanup and settings
  bundle config --global build.nokogiri  "--use-system-libraries" && \
  bundle config --global build.nokogumbo "--use-system-libraries"

WORKDIR /app

COPY Gemfile .
COPY Gemfile.lock .

RUN bundle install --deployment

COPY pivotal_agent .
COPY pivotal_agent.daemon .
COPY /plugins/ /app/plugins/
COPY /config/ /app/config/

RUN bundle package --all

FROM ruby:2-alpine

ENV RAILS_ENV production

RUN apk add --update --virtual --upgrade \
  libxslt-dev \
  && rm -rf /var/cache/apk/*

WORKDIR /app

COPY --from=builder /app/ .
COPY /plugins/ /app/plugins/
COPY /config/ /app/config/

RUN bundle config --global build.nokogiri  "--use-system-libraries" && \
    bundle config --global build.nokogumbo "--use-system-libraries"

RUN bundle install --deployment --without development test --binstubs=/app/vendor/bundle/bin

ENTRYPOINT ["/app/pivotal_agent"]
