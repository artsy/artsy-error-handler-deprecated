_ = require 'underscore'
fs = require 'fs'
jade = require 'jade'
debug = require('debug') 'artsy-error-handler'

render = (res, data) =>
  res.send jade.compile(
    fs.readFileSync(module.exports.template),
    filename: module.exports.template
  )(data)

module.exports.pageNotFound = (req, res, next) ->
  err = new Error
  err.status = 404
  err.message = 'Not Found'
  next err

module.exports.internalError = (err, req, res, next) ->
  debug err.stack
  res.status err.status or 500
  detail = err.message or err.text or err.toString()
  if req.is('application/json')
    res.send
      code: res.statusCode
      message: detail
      stack: err.stack
  else
    # Error templates tend to expect an `asset` local to pull down JS/CSS for
    # the layout but if the CDN fails, or something up the chain above
    # bucket-assets fails then we should still render something.
    res.locals.asset ?= (filename) -> filename
    render res, _.extend
      code: res.statusCode
      error: err
      detail: detail
    , res.locals

module.exports.socialAuthError = (err, req, res, next) ->
  if err.toString().match('User Already Exists')
    # Error urls need to be compatible with Gravity
    params =
      if req.url?.indexOf('facebook') > -1
        "?account_created_email=facebook"
      else if req.url?.indexOf('twitter') > -1
        "?account_created_email=twitter"
      else
        "?error=already-signed-up"
    res.redirect "/log_in#{params}"
  else if err.toString().match('Failed to find request token in session')
    res.redirect '/log_in?error=account-not-found'
  else if err.toString().match('twitter denied')
    res.redirect '/log_in?error=twitter-denied'
  else if err.toString().match("Another Account Already Linked: Twitter")
    res.redirect '/user/edit?error=twitter-already-linked'
  else if err.toString().match("Another Account Already Linked: Facebook")
    res.redirect '/user/edit?error=facebook-already-linked'
  else if err.toString().match "Could not authenticate you"
    res.redirect '/user/edit?error=could-not-auth'
  else
    next err

module.exports.loginError = (err, req, res, next) ->
  res.status switch err.message
    when 'invalid email or password' then 403
    else 500
  res.send { error: err.message }

module.exports.backboneErrorHelper = (req, res, next) ->
  res.backboneError = (model, err) ->
    try
      message = JSON.parse(err.text).error
    catch e
      message = err?.text or err?.response?.text or err?.stack or err?.message
      message ?= try JSON.stringify(err) catch e; 'Unknown Error'
    if err?.status in [404, 403, 401]
      status = 404
      message = 'Not Found'
    else
      status = err?.status or 500
    err = new Error
    err.message = message
    err.status = status
    next err
  next()

