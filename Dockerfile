FROM ruby:2.1.5

# Install Node.js
RUN curl -sL https://deb.nodesource.com/setup_7.x | bash -
RUN apt-get update -qq && apt-get install -y nodejs

# Install package dependencies
RUN apt-get install -y build-essential libpq-dev imagemagick cron libpng12-dev

# Installing dependent gems
RUN gem install therubyracer -v '0.12.1'
RUN gem install libv8 -v '3.16.14.7' -- --with-system-v8

# Making work directory ready for web-app
RUN mkdir /testsite
WORKDIR /testsite
ADD Gemfile /testsite/Gemfile
ADD Gemfile.lock /testsite/Gemfile.lock
ENV RUBY_VERSION=ruby-2.1.5 RAILS_ENV=development
RUN bundle install --jobs 10 --without test

# Copying source-code
ADD . /testsite

# Expose port
EXPOSE 3000

# Cleaning up
RUN rm -rf /var/cache/apt/archives/*.deb

# Running container script
#RUN chmod +x scripts/container-script.sh
CMD (EXECJS_RUNTIME='Node' JRUBY_OPTS="-J-d32 -X-C" bundle exec rake assets:precompile) && (bundle exec rails server)
