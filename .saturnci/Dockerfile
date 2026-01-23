FROM ruby:3.3.5-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libsqlite3-dev \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && echo "saturnci-test" > /etc/machine-id

WORKDIR /code

COPY Gemfile Gemfile.lock ductwork.gemspec ./
COPY lib/ductwork/version.rb ./lib/ductwork/

RUN bundle install

COPY . .

CMD ["bundle", "exec", "rspec"]
