const https = require('https');
const util = require('util');

const CHANNEL = process.env.CHANNEL;
const PATH = process.env.PATH;
const USER_NAME = process.env.USER_NAME;

const STATUS_SEVERITY_MAP = {
  "STOPPED": "warning",
  "IN_PROGRESS": "good",
  "SUCCEEDED": "good",
  "FAILED": "danger"
}


/*
{
  "version": "0",
  "id": "98a0df14-0aa3-41e1-b603-5b27ce3c1431",
  "detail-type": "CodeBuild Build State Change",
  "source": "aws.codebuild",
  "account": "123456789012",
  "time": "2017-07-12T00:42:28Z",
  "region": "us-east-1",
  "resources": [
    "arn:aws:codebuild:us-east-1:123456789012:build/SampleProjectName:6bdced96-e528-485b-a64c-10df867f5f33"
  ],
  "detail": {
    "build-status": "IN_PROGRESS",
    "project-name": "SampleProjectName",
    "build-id": "arn:aws:codebuild:us-east-1:123456789012:build/SampleProjectName:6bdced96-e528-485b-a64c-10df867f5f33",
    "current-phase": "SUBMITTED",
    "current-phase-context": "[]",
    "version": "1"
  }
}
*/

exports.handler = function(event, context) {
    console.log(JSON.stringify(event, null, 2));

    const postData = {
        "channel": CHANNEL,
        "username": USER_NAME
    };

    const buildId = event.detail["build-id"];
    const buildIdParts = buildId.split(":");
    const projectName = event.detail["project-name"];
    const buildStatus = event.detail["build-status"];
    const buildUrl = `https://ap-southeast-2.console.aws.amazon.com/codesuite/codebuild/projects/${projectName}/${buildIdParts[5]}%3A${buildIdParts[6]}`

    const severity = STATUS_SEVERITY_MAP[buildStatus];

    postData.attachments = [
        {
            "color": severity, 
            "fallback": `${projectName} - ${buildStatus}`,
            "fields": [
              {
                "title": projectName,
                "value": `${buildStatus}: <${buildUrl}|${buildId}>`,
                "short": false
              }
            ]
        }
    ];

    var options = {
        method: 'POST',
        hostname: 'hooks.slack.com',
        port: 443,
        path: PATH
    };

    var req = https.request(options, function(res) {
      res.setEncoding('utf8');
      res.on('data', function (chunk) {
        console.log("Request sent");
        context.done(null, postData);
      });
    });
    
    req.on('error', function(e) {
      console.log('problem with request: ' + e.message);
    });    

    req.write(util.format("%j", postData));
    req.end();
};
