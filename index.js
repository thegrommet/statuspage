const querystring = require('querystring')
const {inherits} = require('util')
const SNS = require('aws-sdk/clients/sns')
const {WebClient: SlackClient} = require('@slack/client')

async function main(event) {
  const {description, reporter, urgency} = querystring.parse(event.body)

  if (!isValidUrgency(urgency)) {
    throw new InvalidRequestError("Invalid urgency")
  }

  await sendMessageByUrgency({
    description,
    reporter
  }, urgency)

  return "Submission received"
}

function isValidUrgency(urgency) {
  return ['emergency', 'urgent', 'normal'].includes(urgency)
}

async function sendMessageByUrgency({description, reporter}, urgency, retry = false) {
  try {
    switch (urgency) {
      case 'emergency':
        // post message to sms sns topic and slack
        const sms = {
          Message: description,
          Subject: "TESTING",
          TopicArn: process.env.SMS_TOPIC
        }
        await (new SNS()).publish(sms).promise()

        const slack = new SlackClient(process.env.SLACK_TOKEN)
        await slack.chat.postMessage({
          channel: process.env.SLACK_CHANNEL,
          text: description 
        })
      case 'urgent':
      // post message to email sns topic
        const email = {
          Message: description,
          Subject: "TESTING",
          TopicArn: process.env.EMAIL_TOPIC
        }
        await (new SNS()).publish(email).promise()

      default:
    // create ticket in jira (Cross-region, so can fail more easily)
    }
  } catch (e) {
    console.warn(e.stack)
    if (!retry) {
      // send emergency message about posting failure, including original request
      await sendMessageByUrgency("Initial attempt to notify failed! Treating as emergency.\n" + message, 'emergency', true)
    }
    throw e
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
    const body = await main(event)
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

