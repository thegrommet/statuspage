const querystring = require('querystring')
const {inherits} = require('util')
const SNS = require('aws-sdk/clients/sns')
const {WebClient: SlackClient} = require('@slack/client')
const fetch = require('make-fetch-happen')
const url = require('url')

const headers = {
  'Content-Type': 'text/plain',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST,OPTIONS'
}

async function main(event) {
  const {description, reporter, urgency} = querystring.parse(event.body)

  if (!isValidUrgency(urgency)) {
    throw new InvalidRequestError("Invalid urgency")
  }

  const message = await sendMessageByUrgency({
    description,
    reporter
  }, urgency)

  return message || "Submission received"
}

function isValidUrgency(urgency) {
  return ['emergency', 'urgent', 'normal'].includes(urgency)
}

async function sendMessageByUrgency({description, reporter}, urgency, retry = false) {
  try {

    let ticket = null

    try {
      if (process.env.JIRA_USER && process.env.JIRA_PASSWORD && process.env.JIRA_API_ENDPOINT) {
        // create ticket in jira (Cross-region, so can fail more easily)
        (
        {key: ticket} = await jiraRequest(url.resolve(process.env.JIRA_API_ENDPOINT, '/rest/api/2/issue'), {
          fields: {
            project: {
              key: 'TECH'
            },
            summary: "Request for support",
            labels: ["triage"],
            description: `${description}

Reported by ${reporter}
Expected Reply ${humanUrgency(urgency)}`,
            issuetype: {
              name: 'Task'
            },
            components: [{
              name: "DevOps"
            }]
          }
        }))
      } else {
        console.warn("Skipping JIRA, no configuration present")
      }
    } finally {

      switch (urgency) {
        case 'emergency':
          if (process.env.SMS_TOPIC) {
            // post message to sms sns topic and slack
            const sms = {
              Message: `Eng support request (ticket ${ticket}): ${description}`,
              Subject: "Engineering Support Request",
              TopicArn: process.env.SMS_TOPIC
            }
            await (new SNS()).publish(sms).promise()
          } else {
            console.warn("Skipping SMS, no SMS topic configured")
          }

          if (process.env.SLACK_TOKEN) {
            const slack = new SlackClient(process.env.SLACK_TOKEN)
            await slack.chat.postMessage({
              channel: process.env.SLACK_CHANNEL,
              text: `${description}

Reported by ${reporter}

Ticket ${ticket}`
            })
          } else {
            console.warn("Skipping slack, no token present")
          }
        case 'urgent':
          if (process.env.EMAIL_TOPIC) {
            // post message to email sns topic
            const email = {
              Message: description,
              Subject: "Engineering Support Request",
              TopicArn: process.env.EMAIL_TOPIC
            }
            await (new SNS()).publish(email).promise()
          } else {
            console.warn("Skipping email, no email topic configured")
          }

        default:

          return {
            statusCode: 200,
            body: `A JIRA ticket has been created. <a href='${url.resolve(process.env.JIRA_API_ENDPOINT, `/browse/${ticket}`)}'>${ticket}</a>`,
            headers: Object.assign({}, headers, {
              'content-type': 'text/html'
            })
          }
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
    return typeof body == 'string' ? {
      statusCode: 200,
      body,
      headers
    } : body

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

function humanUrgency(urgency) {
  if (urgency == 'emergency') return 'ASAP'
  if (urgency == 'urgent') return 'Next business day'
  if (urgency == 'normal') return 'This week'
  return 'Unknown'
}
