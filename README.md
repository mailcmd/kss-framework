<h1>WORK IN PROGRESS, STILL NOT USABLE!</h1>

# KSS Framework

KSS-FW is a tiny elixir/js framework for web development. 

## Concepts

KSS-framework has etentially a javascript client library (KSS-js) that allow to build reactive 
web pages, i.e, changing some property of an object, automatically update the page content. 

Also has a server side component (KSS-server) developed in Elixir language that open a HTTP 
server, a WebSocket server and a EventSource script server. 

## How to install?
```bash
$ mix new <app_name>
$ cd <app_name>

## Edit your mix.exs and add in deps:
## {:kss, git: "http://gitlab.vianet.com.ar:3000/msante/kss-framework.git"}

$ mix deps.get
$ mkdir -p config/local
$ cp deps/kss/config/config.exs config/
$ cp deps/kss/config/local.config.exs.example config/local/config.exs

## Edit config/local/config.exs
## Set modules :websocket_manager y :app_supervisor (mandatory)

$ cp -R deps/kss/priv/layout priv/

$ git clone https://github.com/mailcmd/kss-js.git
$ cp kss-js/kss.js priv/layout/js/
$ cp kss-js/dproxy.js priv/layout/js/
$ rm -rf kss-js
$ mkdir -p priv/www

## PUT YOUR KSS WEB SITE IN /priv/www 

$ iex -S mix 

## Good look!
```

## Doc 

Not yet.
