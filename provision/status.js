const AWS            = require("aws-sdk");
const route53        = new AWS.Route53();
const s3             = new AWS.S3();
const secretsmanager = new AWS.SecretsManager();
const https          = require('https');
const util           = require('util');


var CHANNEL = process.env.CHANNEL;
var PATH = process.env.PATH;
var USER_NAME = process.env.USER_NAME;
var ICON_EMOJI = process.env.ICON_EMOJI;

const getConfiguration = async () => {
    var params = {
        SecretId: "${secretId}"
    };
    return await secretsmanager.getSecretValue(params).promise();
};

const putConfiguration = async (configuration) => {
    var params = {
        SecretId: "${secretId}", 
        SecretString: configuration
    };
    return await secretsmanager.putSecretValue(params).promise();
};

const putStatusDocument = async (document) => {
    const params = {
      Body: document, 
      Bucket: "status.example.com", 
      Key: "status.json",
      ACL: "public-read"
    };
    console.log("Updating status document");
    return await s3.putObject(params).promise();
};

const listHealthChecks = async () => {
    const params = {
      MaxItems: '100'
    };
    return await route53.listHealthChecks(params).promise();
};

const getHealthCheckStatus = async (healthCheckId) => {
    console.log(`Get health check status $${healthCheckId}`);
    const params = {
      HealthCheckId: healthCheckId
    };
    return await route53.getHealthCheckStatus(params).promise();
};

const sendSlackNotification = async (postText, severity) => {
    return new Promise((resolve, reject) => {
        const postData = {
            "channel": CHANNEL,
            "username": USER_NAME,
            "icon_emoji": ICON_EMOJI
        };

        postData.attachments = [
            {
                "color": severity, 
                "text": postText
            }
        ];

        const options = {
            method: 'POST',
            hostname: 'hooks.slack.com',
            port: 443,
            path: PATH
        };

        const req = https.request(options, res => {
            res.setEncoding('utf8');
            res.on('data', chunk => {
                resolve();
            });
        });
        
        req.on('error', function(e) {
            reject(e);
        });    

        req.write(util.format("%j", postData));
        req.end();
    });
};

exports.handler = async (event, context, callback) => {
    let statusReport = {
        services: []
    };
    
    const configuration = await getConfiguration();
    let currentAlerts = configuration.SecretString;
    const healthCheckList = await listHealthChecks();
    console.log(JSON.stringify(healthCheckList));
    await Promise.all(healthCheckList.HealthChecks.map(async healthCheckListItem => {
        try {
           let healthCheckStatus = await getHealthCheckStatus(healthCheckListItem.Id);
           console.log(JSON.stringify(healthCheckStatus));
           
           const statusCount = healthCheckStatus.HealthCheckObservations.length;
           let failedCount = 0;
           let warningMessage = "";
           healthCheckStatus.HealthCheckObservations.map(observation => {
             if (observation.StatusReport.Status.substr(0, 7) !== "Success") {
                 failedCount += 1;
                 if (warningMessage.indexOf(observation.StatusReport.Status) < 0) {
                    warningMessage = `$${warningMessage}$${observation.StatusReport.Status}, `;
                 }
             }
           });
           
           statusReport.services.push({
               name: healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName,
               status: failedCount == 0 ? "service--green" : failedCount == statusCount ? "service--red" : "service--orange",
               message : warningMessage
           });

            if (failedCount > 0 && !currentAlerts.includes(healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName)) {
                let slackMessage = `$${healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName} is down`;
                let slackSeverity = "danger";
                if (failedCount < statusCount) {
                    slackMessage = `$${healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName} may be failing`;
                    slackSeverity = "warning";
                }
                await sendSlackNotification(slackMessage, slackSeverity);
                currentAlerts = `$${currentAlerts},$${healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName}`;
            } else if (failedCount == 0 && currentAlerts.includes(healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName)) {
                slackMessage = `$${healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName} is back up`;
                slackSeverity = "good";

                await sendSlackNotification(slackMessage, slackSeverity);
                currentAlerts = currentAlerts.replace(`,$${healthCheckListItem.HealthCheckConfig.FullyQualifiedDomainName}`, "");
            }
        } catch (err) {
            console.log(err, err.stack);
            callback(err.message);
        }
    }));
    
    await putConfiguration(`$${currentAlerts.trim()} `);
    try {
        console.log(JSON.stringify(statusReport));
        await putStatusDocument(JSON.stringify(statusReport));
    } catch (err) {
        console.log(err, err.stack);
        callback(err.message);
    }
    
    callback(null, "Success");
};
