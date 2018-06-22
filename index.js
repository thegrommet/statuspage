const querystring = require('querystring')
const {inherits} = require('util')

function main(event) {
  const {description, reporter, urgency} = querystring.parse(event.body)

  if (!isValidUrgency(urgency)) {
    throw new InvalidRequestError("Invalid urgency")
  }

  sendMessageByUrgency({
    description,
    reporter
  }, urgency)

  return "Submission received"
}

function isValidUrgency(urgency) {
	return ['emergency', 'urgent', 'normal'].includes(urgency)
}

function sendMessageByUrgency(message, urgency) {
  try {
    switch (urgency) {
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
      body,
      headers: {
        'content-type': 'text/plain'
      }
    }

  } catch (e) {
    console.warn(e.stack)
    const statusCode = e.statusCode || 500
    return {
      statusCode,
      body: e.statusCode ? e.message : "Internal server error",
      headers: {
        'content-type': 'text/plain'
      }
    }
  }
}

