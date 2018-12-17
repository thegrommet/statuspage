const querystring = require('querystring')
const {inherits} = require('util')
const SNS = require('aws-sdk/clients/sns')
const {WebClient: SlackClient} = require('@slack/client')
const fetch = require('make-fetch-happen')
const url = require('url')
const multipart = require('aws-lambda-multipart-parser')

async function main(event) {
  const {description, reporter, urgency} = /^multipart/.test(event.headers['content-type']) ? multipart.parse(event) : querystring.parse(event.body)

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
        if (process.env.SMS_TOPIC) {
          // post message to sms sns topic and slack
          const sms = {
            Message: description,
            Subject: "Request for support",
            TopicArn: process.env.SMS_TOPIC
          }
          await (new SNS()).publish(sms).promise()
        }

        if (process.env.SLACK_TOKEN) {
          const slack = new SlackClient(process.env.SLACK_TOKEN)
          await slack.chat.postMessage({
            channel: process.env.SLACK_CHANNEL,
            text: description
          })
        }
      case 'urgent':
        if (process.env.EMAIL_TOPIC) {
          // post message to email sns topic
          const email = {
            Message: description,
            Subject: "Request for support",
            TopicArn: process.env.EMAIL_TOPIC
          }
          await (new SNS()).publish(email).promise()
        }

      default:
        if (process.env.JIRA_USER && process.env.JIRA_PASSWORD && process.env.JIRA_API_ENDPOINT) {
          // create ticket in jira (Cross-region, so can fail more easily)
          await jiraRequest(url.resolve(process.env.JIRA_API_ENDPOINT, '/rest/api/2/issue'), {
            fields: {
              project: {
                key: 'TECH'
              },
              summary: "Request for support",
              labels: ["triage"],
              description: description + "\n\n" + `Reported by ${reporter}`,
              issuetype: {
                name: 'Task'
              },
              components: [{
                name: "DevOps"
              }]
            }
          })
        }
    }
  } catch (e) {
    console.warn(`Error sending message the first time: ${e.stack}`)
    if (!retry) {
      // send emergency message about posting failure, including original request
      await sendMessageByUrgency({
        reporter,
        description: "Initial attempt to notify failed! Treating as emergency.\n" + description
      }, 'emergency', true)
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

const headers = {
  'Content-Type': 'text/plain',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST,OPTIONS'
}

exports.handler = async function(event, context) {
  console.warn(JSON.stringify(event))
  if (event.httpMethod == "OPTIONS") {
    return {
      statusCode: 200,
      body: '',
      headers
    }
  }

  try {
    const body = await main(event)
    return {
      statusCode: 200,
      body,
      headers
    }

  } catch (e) {
    console.warn(e.stack)
    const statusCode = e.statusCode || 500
    return {
      statusCode,
      body: e.statusCode ? e.message : "Internal server error",
      headers
    }
  }
}


async function jiraRequest(url, body) {
  console.warn({
    request: body
  })
  const auth = Buffer.from(`${process.env.JIRA_USER}:${process.env.JIRA_PASSWORD}`).toString('base64')
  const req = {
    body: JSON.stringify(body),
    method: body ? 'POST' : 'GET',
    headers: {
      'content-type': 'application/json',
      'authorization': `Basic ${auth}`
    }
  }
  const res = await fetch(url, req)
  if (res.ok) {
    const ret = await res.json()
    console.warn({
      response: ret
    })
    return ret
  } else {
    const err = await res.json()
    console.warn({
      response: err
    })
    const errMessage = err && err.errorMessages ? err.errorMessages.join('\n') : res.statusText
    throw Object.assign(new Error(errMessage), {
      statusCode: res.status
    })
  }
}
