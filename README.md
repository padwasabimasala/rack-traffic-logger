# Rack::TrafficLogger

This is simple Rack middleware for logging incoming/outgoing HTTP/S traffic.

## Installation

```bash
gem install rack-traffic-logger
```

## Usage

```ruby
require 'rack/traffic_logger'
```

Then, in your `config.ru` or wherever you set up your middleware stack:

```ruby
use Rack::TrafficLogger, 'path/to/file.log'
```

By default, simple stream-like output will be written:

```
@ Wed 12 Nov '14 15:19:48.0 #48f8ed62
GET /home HTTP/1.1

@ Wed 12 Nov '14 15:19:48.0 #48f8ed62
HTTP/1.1 200 OK
```

The part after the `#` is the **request log ID**, which is unique to each request. It lets you match up a response with its request, in case you have multiple listeners.

You can add some colour, and JSON request/response body pretty-printing, by specifying a formatter:

```ruby
use Rack::TrafficLogger, 'file.log', Rack::TrafficLogger::Formatter::Stream.new(color: true, pretty_print: true)
```

You can also output JSON (great for sending to log analyzers like Splunk):

```ruby
use Rack::TrafficLogger, 'file.log', Rack::TrafficLogger::Formatter::JSON.new
```

### Filtering

By default, only basic request/response details are logged:

```json
{
  "timestamp": "2014-11-12 15:30:20 +1100",
  "request_log_id": "d67e5591",
  "event": "request",
  "SERVER_NAME": "localhost",
  "REQUEST_METHOD": "GET",
  "PATH_INFO": "/home",
  "HTTP_VERSION": "HTTP/1.1",
  "SERVER_PORT": "80",
  "QUERY_STRING": "",
  "REMOTE_ADDR": "127.0.0.1"
}
{
  "timestamp": "2014-11-12 15:30:20 +1100",
  "request_log_id": "d67e5591",
  "event": "response",
  "http_version": "HTTP/1.1",
  "status_code": 200,
  "status_name": "OK"
}
```

You can specify other parts of requests/responses to be logged:

```ruby
use Rack::TrafficLogger, 'file.log', :request_headers, :response_bodies
```

Optional sections include `request_headers`, `request_bodies`, `response_headers`, and `response_bodies`. You can also specify `headers` for both request and response headers, and `bodies` for both request and response bodies. Or, specify `all` if you want the lot. Combine tokens to get the output you need:

```ruby
use Rack::TrafficLogger, 'file.log', :headers, :response_bodies # Everything except request bodies!
# Or:
use Rack::TrafficLogger, 'file.log', :all # Everything
```

If you want to use a custom formatter, make sure you include it before any filtering arguments:

```ruby
use Rack::TrafficLogger, 'file.log', Rack::TrafficLogger::Formatter::JSON.new, :headers
```

You can specify that you want different parts logged based on the kind of request that was made:

```ruby
use Rack::TrafficLogger, 'file.log', :headers, post: :request_bodies # Log headers for all requests, and also request bodies for POST requests
```

You can also exclude other request verbs entirely:

```ruby
use Rack::TrafficLogger, 'file.log', only: {post: [:headers, :request_bodies]} # Log only POST requests, and include all headers, and request bodies
```

This can be shortened to:

```ruby
use Rack::TrafficLogger, 'file.log', :post, :headers, :request_bodies
```

Or if you only want the basics of POST requests, without headers/bodies:

```ruby
use Rack::TrafficLogger, 'file.log', :post
```

You can apply the same filtration based on response status codes:

```ruby
use Rack::TrafficLogger, 'file.log', 404 # Only log requests that are not-found
```

Include as many as you like, and even use ranges:

```ruby
use Rack::TrafficLogger, 'file.log', 301, 302, 400...600 # Log redirects and errors
```

If you need to, you can get pretty fancy:

```ruby
use Rack::TrafficLogger, 'file.log', :request_headers, 401 => false, 500...600 => :all, 200...300 => {post: :request_bodies, delete: false}
use Rack::TrafficLogger, 'file.log', [:get, :head] => 200..204, post: {only: {201 => :request_bodies}}, [:put, :patch] => :all
```
