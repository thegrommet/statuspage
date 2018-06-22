const querystring = require('querystring')
const {inherits} = require('util')

function main(event) {
  const {description, reporter, priority} = querystring.parse(event.body)

  if (!isValidPriority(priority)) {
    throw new InvalidRequestError("Invalid priority")
  }

  sendMessageByPriority({
    description,
    reporter
  }, priority)

  return {
    message: "Submission received"
  }
}

function isValidPriority(priority) {
	return ['emergency', 'urgent', 'normal'].includes(priority)
}

function sendMessageByPriority(message, priority) {
  try {
    switch (priority) {
      case 'emergency':
      // post message to sms sns topic and slack
      case 'urgent':
      // post message to email sns topic
      default:
    // create ticket in jira (Cross-region, so can fail more easily)
    }
  } catch (e) {
    // send emergency message about posting failure, including original request
  }
}


class InvalidRequestError extends Error {
  constructor(...rest) {
    super(...rest)
    this.statusCode = 400
  }
}

exports.handler = async function(event, context) {
  try {
    const body = main(event)
    return {
      statusCode: 200,
      body: JSON.stringify(body),
      headers: {
        'content-type': 'application/json'
      }
    }

  } catch (e) {
    console.warn(e.stack)
    const statusCode = e.statusCode || 500
    return {
      statusCode,
      body: JSON.stringify({
        message: e.statusCode ? e.message : "Internal server error"
      }),
      headers: {
        'content-type': 'application/json'
      }
    }
  }
}

