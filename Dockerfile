FROM ruby:2.3.0

RUN apt-get update \
    && apt-get upgrade -y

RUN apt-get install nodejs -y
RUN apt-get install -y postgresql postgresql-contrib

RUN mkdir -p /app
WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem install bundler
RUN bundle config set --local path 'vendor/bundle'
RUN bundle install

COPY . .

EXPOSE 5432 3000

CMD bundle exec rails server -p 3000 -b 0.0.0.0
