# Engineering Support Request Form

## Fields

- Describe the problem (`description`)
- What's your email address? (`reporter`)
- How soon do you expect a response? (`priority`)
  - Immediately (`emergency`)
  - Next business day (`urgent`)
  - This week (`normal`)

### Notable omissions

- Only three levels of priority. Discerning more is not something people can do easily without more global information like relative importance of multiple requests
- Name (identify by email only, so there's a point of contact to reply to)
- Title of ticket. This always evolves over time and is best with more context, rather than what the requester thinks the title should be. This can be set in triage.

## Message Routing

- `emergency` -> SMS, Slack, Email & Jira ticket for postmortem or followup
- `urgent` -> Email alert & Jira ticket for action
- `normal` -> Jira ticket for triage

## Design

```
   +-----------------------------+
   |                             |
   |  Instructional text         |
   |                             |
   |  Messaging to the company   |
   |                             |
   +-----------------------------+
   |                             |
   |  The Form                   |
   |                             |
   |  [ Email Address ]          |
   |                             |
   |  [ Description   ]          |
   |  [               ]          |
   |  [               ]          |
   |                             |
   |  ( ) Immediately            |
   |  ( ) Next business day      |
   |  (*) This Week              |
   |                             |
   |              [ Send ]       |
   +-----------------------------+
```

### Small Touches

- Set localstorage to remember email address for next time
- Beside the description field, talk about what makes a good report that can be acted on

## Deployment

Terraform to push to AWS

Form hosted in Github (`internalsupport.thegrommet.com`?), so it works even if Amazon us-east-1 goes bananas.

Posts to a lambda function hosted in us-west-2

## Logic

```javascript
try {
    switch (urgency) {
    case 'emergency':
        // post message to sms sns topic
    case 'urgent':
        // post message to email sns topic
    default:
        // create ticket in jira (Cross-region, so can fail more easily)
	}
} catch (e) {
     // send emergency message about posting failure, including original request
}
```

## Jira Ticket

Create a GROM ticket or a TECH ticket?

Mark `triage`

If emergency, describe as needing followup

Set title to `Request from engineering support form (timestamp)` for later editing.

## Undecided

- Name of the site/bucket hosting the page
- What project should JIRA tickets end up in?
- Should we reject non-grommet email addresses as requesters?
