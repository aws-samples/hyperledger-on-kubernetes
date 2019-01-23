'use strict';

const FabricCAServices = require('fabric-ca-client');
const Client = require('fabric-client');
const logger = Client.getLogger('gw');
const { FileSystemWallet, Gateway, X509WalletMixin } = require('fabric-network');
const util = require('util')
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
//const yaml = require('yaml');
const connection = require('./connection.js');
const walletPath = path.join(process.cwd(), 'wallet');
const wallet = new FileSystemWallet(walletPath);
const gateway = new Gateway();
const { exec } = require('child_process');
const { execFile } = require('child_process');
var CONFIG = require('./config.json');

let configtxContents = '';
let dataPath = CONFIG.datapath;
let configtxFilename = CONFIG.configtxfile;
let scriptPath = CONFIG.scriptpath;
let envFilename = CONFIG.envfile;
let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));
let client;

// this is the default name given to the orderer system channel when booting the Fabric network
// unless you have overridden this
let systemChannelName = 'testchainid';

// This is a little hack. It loads the file env.sh as a list of properties so that I can easily refer to a property in the code
require('dotenv').config({ path: path.join(scriptPath, envFilename) })
console.log(process.env);

async function enrollAdmin() {
    try {
        // Check to see if we've already enrolled the admin user.
        const adminExists = await wallet.exists('admin');
        if (adminExists) {
            logger.info('An identity for the admin user "admin" already exists in the wallet');
            logger.info('Wallet identities: ' + util.inspect(wallet.list()));
            logger.info('Wallet admin exists: ' + util.inspect(wallet.exists('admin')));
            return;
        }

        // Create a new CA client for interacting with the CA.
        const caURL = ccp.certificateAuthorities['ca-org1'].url;
        logger.info('CA URL: ' + caURL);
        const ca = new FabricCAServices(caURL);

        // Enroll the admin user, and import the new identity into the wallet.
        const enrollment = await ca.enroll({ enrollmentID: ccp.certificateAuthorities['ca-org1'].registrar[0].enrollId, enrollmentSecret: ccp.certificateAuthorities['ca-org1'].registrar[0].enrollSecret });
        const identity = X509WalletMixin.createIdentity('org1MSP', enrollment.certificate, enrollment.key.toBytes());
        logger.info(`Wallet path: ${walletPath}`);
        await wallet.import('admin', identity);
        logger.info('Successfully enrolled admin user "admin" and imported it into the wallet');
        logger.info('Wallet identities: ' + util.inspect(wallet.list()));
        logger.info('Wallet admin exists: ' + util.inspect(wallet.exists('admin')));
    } catch (error) {
        logger.error(`Failed to enroll admin user "admin": ${error}`);
    }
}
async function adminGateway() {

        // Set connection options; identity and wallet
        let connectionOptions = {
          identity: 'admin',
          wallet: wallet,
          discovery: { enabled:true, asLocalhost:false }
        };

        // Connect to gateway using application specified parameters
        logger.info('Connecting to Fabric gateway.');

        await gateway.connect(ccp, connectionOptions);
        client = gateway.getClient();
}

async function listNetwork() {

    logger.info('Printing out the Fabric network');
    logger.info('Client: ' + util.inspect(client));
    logger.info('ClientConfig: ' + util.inspect(client.getClientConfig()));
    let msp = client.getMspid();
    logger.info('msp: ' + util.inspect(msp));
    let peers = client.getPeersForOrg();
    logger.info('peers: ' + util.inspect(peers));

}

// Loads configtx.yaml into a Javascript object for easy querying
async function loadConfigtx() {

    try {
        logger.info('Loading the Fabric configtx.yaml at path: ' + path.join(dataPath, configtxFilename));
        configtxContents = yaml.safeLoad(fs.readFileSync(path.join(dataPath, configtxFilename), 'utf8'));
        logger.info('Configtx loaded at path: ' + dataPath);
    } catch (error) {
        logger.error('Failed to loadConfigtx: ' + error);
        throw error;
    }

}

async function backupFile(absoluteFilename) {

    try {
        let filename = path.join(absoluteFilename + Math.floor(Date.now() / 1000));
        logger.info('Backing up original file: ' + absoluteFilename + '. Backup file titled: ' + filename);
        fs.copyFileSync(absoluteFilename, filename);
    } catch (error) {
        logger.error('Failed to backup file: ' + error);
        throw error;
    }
}

// Get the list of organisations that are configured in configtx.yaml
async function getOrgsFromEnv() {

    try {
        let orgString = process.env.PEER_ORGS;
        let orgArray = orgString.split(" ");
        logger.info("Orgs in env.sh for this network are: " + orgString);
        return orgArray;
    } catch (error) {
        logger.error('Failed to getOrgsFromEnv: ' + error);
        throw error;
    }
}

// Get the list of organisations that are configured in configtx.yaml
async function getOrgsFromConfigtx() {

    let orgs = [];
    try {
        await loadConfigtx();
        for (let org in configtxContents['Organizations']) {
            logger.info("Orgs in configtx for this network are: " + configtxContents['Organizations'][org]['Name'] + ' with MSP ' + configtxContents['Organizations'][org]['ID']);
            orgs.push(configtxContents['Organizations'][org]['Name']);
        }
        return orgs;
    } catch (error) {
        logger.error('Failed to getOrgsFromConfigtx: ' + error);
        throw error;
    }
}


// Get the list of profiles that are configured in configtx.yaml
async function getProfilesFromConfigtx() {

    let profiles = [];
    try {
        await loadConfigtx();
        for (let profile in configtxContents['Profiles']) {
            logger.info("Profiles in configtx for this network are: " + profile);
            profiles.push(profile.toString());
        }
        return profiles;
    } catch (error) {
        logger.error('Failed to getProfilesFromConfigtx: ' + error);
        throw error;
    }
}

// This will create a new org to both the configtx.yaml and env.sh config files
// The new org also needs to be added to the consortium, which is defined in the orderer system channel, which
// is created from the orderer genesis block when the Fabric network is booted
//
// TODO: the anchor peer needs to be passed to this function, and updated into configtx.yaml
async function addOrg(args) {

    let org = args['org'];
    try {
        logger.info('Adding a new org to configtx.yaml and env.sh: ' + org);
        // Validate that the org does not already exist
        let orgsInConfig = await getOrgsFromConfigtx();
        //Check that the new org to be added does not already exist in configtx.yaml
        if (orgsInConfig.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in configtx.yaml. These orgs are already present: ' + orgsInConfig);
        } else {
            await addOrgToConfigtx(org);
        }

        let orgsInEnv = await getOrgsFromEnv();
        //Check that the new org to be added does not already exist in env.sh
        if (orgsInEnv.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in env.sh. These orgs are already present: ' + orgsInEnv);
        } else {
            await addOrgToEnv(org);
        }
        logger.info('Added a new org to configtx.yaml and env.sh');

        logger.info('Adding new org to consortium');
        await addOrgToConsortium({"org": org, "channelname": systemChannelName});

        return {"status":200,"message":"Org added to configtx.yaml and env.sh. New org is: " + org}
    } catch (error) {
        logger.error('Failed to addOrg: ' + error);
        throw error;
    }
}


// This will create a new org in configtx.yaml, by copying an existing org
//
// TODO: the anchor peer needs to be passed to this function, and updated into configtx.yaml
async function addOrgToConfigtx(org) {

    try {
        let orgsInConfig = await getOrgsFromConfigtx();
        //Check that the new org to be added does not already exist in configtx.yaml
        if (orgsInConfig.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in configtx.yaml. These orgs are already present: ' + orgsInConfig);
            return;
        }
        let configtxFilepath = path.join(dataPath, configtxFilename);
        await backupFile(configtxFilepath);

        // Use the template to add a new org to configtx.yaml
        let contents = "";
        fs.readFileSync(configtxFilepath).toString().split('\n').forEach(function (line) {
            contents += line + "\n";
            let ix = line.toString().indexOf("Organizations:");
            if (ix > -1 && ix < 2) {
                logger.info('Found the Organizations section in configtx.yaml - writing new org here');
                let data = fs.readFileSync ('./templates/org.yaml', 'utf8');
                let result = data.replace(/%org%/g, org);
                contents += result + "\n";
                logger.info('Added new org section to configtx.yaml');
            }
        });
        fs.writeFileSync(dataPath + configtxFilename, contents);
        logger.info('Added a new org to configtx.yaml at path: ' + dataPath);
        return {"status":200,"message":"Org added to configtx.yaml: " + org}
    } catch (error) {
        logger.error('Failed to addOrgToConfigtx: ' + error);
        throw error;
    }
}

// This will create a new org in env.sh
async function addOrgToEnv(org) {

    try {
        let orgsInEnv = await getOrgsFromEnv();
        //Check that the new org to be added does not already exist in env.sh
        if (orgsInEnv.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in env.sh. These orgs are already present: ' + orgsInEnv);
            return;
        }
        let envFilepath = path.join(scriptPath, envFilename);
        await backupFile(envFilepath);

        // Use the template to add a new org to env.sh
        let contents = "";
        orgsInEnv.push(org);
        fs.readFileSync(envFilepath).toString().split('\n').forEach(function (line) {
            let ix = line.toString().indexOf("PEER_ORGS=");
            if (ix > -1 && ix < 2) {
                logger.info('Found the PEER_ORGS section in env.sh - adding new org to this env variable');
                let result = 'PEER_ORGS="' + orgsInEnv.join(" ") + '"'
                contents += result + "\n";
                logger.info('Updated PEER_ORGS in env.sh to:' + result);
            } else {
                ix = line.toString().indexOf("PEER_DOMAINS=");
                if (ix > -1 && ix < 2) {
                    logger.info('Found the PEER_DOMAINS section in env.sh - adding new org to this env variable');
                    let result = 'PEER_DOMAINS="' + orgsInEnv.join(" ") + '"'
                    contents += result + "\n";
                    logger.info('Updated PEER_DOMAINS in env.sh to:' + result);
                } else {
                    contents += line + "\n";
                }
            }
        });
        fs.writeFileSync(envFilepath, contents);
        logger.info('Added a new org to env.sh at path: ' + dataPath);
        return {"status":200,"message":"Org added to env.sh: " + org}
    } catch (error) {
        logger.error('Failed to addOrgToEnv: ' + error);
        throw error;
    }
}

// This will create a new profile in configtx.yaml, which can be used for creating new channels
// I have tried to edit this file using the js-yaml, yaml libraries. Neither of them support anchors in YAML, so
// the resulting YAML is written incorrectly and cannot be processed by configtxgen. I've therefore taken to
// manually reading and writing the file, without using YAML
async function addConfigtxProfile(args) {

    let profileName = args['profilename'];
    let orgs = args['orgs']; // orgs to be included in the profile
    try {
        let profilesInConfig = await getProfilesFromConfigtx();
        //Check that the new profile to be added does not already exist in configtx.yaml
        if (profilesInConfig.indexOf(profileName) > -1) {
            logger.error('Profile: ' + profileName + ' already exists in configtx.yaml. These profiles are already present: ' + profilesInConfig);
            return;
        }
        let orgsInConfig = await getOrgsFromConfigtx();
        //Check that the orgs to be used in the profile already exist in configtx.yaml
        for (let org of orgs) {
            if (orgsInConfig.indexOf(org) < 0) {
                logger.error('Org: ' + org + ' does not exist in configtx.yaml - you cannot create a profile that uses this org. These orgs are already present: ' + orgsInConfig);
                return;
            }
        }
        let configtxFilepath = path.join(dataPath, configtxFilename);
        await backupFile(configtxFilepath);
        let fd;

        // Use the template to add a new profile to configtx.yaml
        try {
            let data = fs.readFileSync('./templates/profile.yaml', 'utf8');
            let result = data.replace(/%profile%/g, profileName);
            let ix = result.toString().indexOf("%org%");
            if (ix > -1) {
                for (let org of orgs) {
                    result = result.slice(0, ix) + org + "\n            - *" + result.slice(ix);
                }
                //Insert the new orgs before the placeholder %org%, then remove the placeholder
                ix = result.toString().indexOf("- *%org%");
                if (ix > -1) {
                    result = result.slice(0, ix) + result.slice(ix + 9);
                }
            }
            fd = fs.openSync(configtxFilepath, 'a');
            fs.appendFileSync(fd, result, 'utf8');
            logger.info('Appending a new profile to configtx.yaml for profile: ' + profileName);

        } catch (err) {
            logger.error('Failed to addConfigtxProfile: ' + error);
        } finally {
            if (fd !== undefined)
                fs.closeSync(fd);
        }

        logger.info('Appended a new profile to configtx.yaml at path: ' + dataPath);
        return {"status":200,"message":"Profile added to configtx.yaml: " + profileName}
    } catch (error) {
        logger.error('Failed to addConfigtxProfile: ' + error);
        throw error;
    }
}

// This will generate a new transaction config, used to create a new channel
async function createTransactionConfig(args) {

    let profileName = args['profilename'];
    let channelName = args['channelname'];
    logger.info('Generating a transaction config for profile/channel: ' + args);
    if (!(profileName && channelName)) {
        logger.error('Both profileName and channelName must be provided to generate a transaction config');
        logger.error('Failed to createTransactionConfig');
    }
    let profilesInConfig = await getProfilesFromConfigtx();
    //Check that the new profile to be added does not already exist in configtx.yaml
    if (profilesInConfig.indexOf(profileName) < 0) {
        logger.error('Profile: ' + profileName + ' does not exist in configtx.yaml - cannot generate a transaction config. These profiles are already present: ' + profilesInConfig);
        return;
    }
    let cmd = "kubectl exec -it $(kubectl get pod -l name=cli -o jsonpath=\"{.items[0].metadata.name}\" -n org0) -n org0 -- bash -c \"cd /data; export FABRIC_CFG_PATH=/data; configtxgen -profile " + profileName + " -outputCreateChannelTx " + channelName + ".tx -channelID " + channelName + "\"";

    try {
        logger.info('Generating channel configuration: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Failed to generate channel configuration transaction');
            logger.error(err);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        logger.info('Generated a transaction config for profile/channel: ' + args + ". Check ls -lt /opt/share/rca-data for the latest .tx file");
        return {"status":200,"message":"Created channel configuration transaction file - Check ls -lt /opt/share/rca-data for the latest .tx file"}
    } catch (error) {
        logger.error('Failed to createTransactionConfig: ' + error);
    }
}


async function createChannel(args) {

    let channelName = args['channelname'];
    logger.info('Creating new channel: ' + channelName);
    let scriptName = 'scripts-for-api/create-channel.sh';
    let localScriptPath = path.resolve(__dirname, scriptName);
    // Copy the file to the /opt/share/rca-scripts directory. This will make it available to the /scripts directory
    // inside the CLI container
    try {
        logger.info('Copying script file that will be executed: ' + localScriptPath + '. to: ' + scriptPath);
        fs.copyFileSync(localScriptPath, path.join(scriptPath, "create-channel.sh"));
    } catch (error) {
        logger.error('Failed to copy the script file: ' + error);
        throw error;
    }

    let cmd = "kubectl exec -it $(kubectl get pod -l name=cli -o jsonpath=\"{.items[0].metadata.name}\" -n org0) -n org0 -- bash -c \"bash /scripts/create-channel.sh " + channelName + "\"";

    try {
        logger.info('Executing cmd: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Error during exec - failed to create channel: ' + channelName);
            logger.error(err);
            logger.info(`stdout: ${stdout}`);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"Created new channel: " + channelName}
    } catch (error) {
        logger.error('Failed to create channel: ' + error);
        throw error;
    }




//
//    let signatures = [];
//    logger.info('Creating channel: ' + channelName + ' using transaction config file: ' + channelName + ".tx");
//    try {
////        let userorg = "org1";
////        let username = userorg + 'user';
////        let userdetails = {"username":username,"org":userorg};
////    	let response = await connection.getRegisteredUser(userdetails, true);
////        let caClient = client.getCertificateAuthority();
////        logger.info('##### getRegisteredUser - Got caClient %s', util.inspect(caClient));
////        let adminUserObj = await client.setUserContext({username: caClient._registrar[0].enrollId, password: caClient._registrar[0].enrollSecret});
////
//        // Set connection options; identity and wallet
//        let connectionOptions = {
//          identity: 'admin',
//          wallet: wallet,
//          discovery: { enabled:true, asLocalhost:false }
//        };
//
//        // Connect to gateway using application specified parameters
//        logger.info('Connecting to Fabric gateway.');
//
//        await gateway.connect(ccp, connectionOptions);
//        client = gateway.getClient();
//
//        // first read in the file, this gives us a binary config envelope
//        let envelope_bytes = fs.readFileSync(path.join(dataPath, channelName + ".tx"));
//        // have the nodeSDK extract out the config update
//        var config_update = await client.extractChannelConfig(envelope_bytes);
//
////        //get the client used to sign the package
////        let userorg = "org1";
////        let username = userorg + 'user';
////        let userdetails = {"username":username,"org":userorg};
////    	let response = await connection.getRegisteredUser(userdetails, true);
////        logger.info('getRegisteredUser response: ' + util.inspect(response));
////        client = await connection.getClientForOrg(userorg, username);
////        if(!client) {
////			throw new Error(util.format('User was not found :', username));
////		} else {
////			logger.debug('User %s was found to be registered and enrolled', username);
////        }
//
//
//
//        var signature = client.signChannelConfig(config_update);
//        signatures.push(signature);
//
////        //get the client used to sign the package
////        userorg = "org2";
////        username = userorg + 'user';
////        userdetails = {"username":username,"org":userorg};
////    	response = await connection.getRegisteredUser(userdetails, true);
////        logger.info('getRegisteredUser response: ' + util.inspect(response));
////        client = await connection.getClientForOrg(userorg, username);
////        if(!client) {
////			throw new Error(util.format('User was not found :', username));
////		} else {
////			logger.debug('User %s was found to be registered and enrolled', username);
////        }
////        signature = client.signChannelConfig(config_update);
////        signatures.push(signature);
//
//        // create an orderer object to represent the orderer of the network
//        logger.info('Connecting to orderer: ' + ordererUrl);
//        var orderer = client.newOrderer(ordererUrl);
////        var orderer = client.newOrderer(ordererUrl, {"pem":"/opt/share/rca-data/org0-ca-chain.pem"});
//
//        // have the SDK generate a transaction id
//        let tx_id = client.newTransactionID();
//        logger.info('Creating channel - tx_id: ' + tx_id);
//
//        let request = {
//          config: config_update, //the binary config
//          signatures : [signature], // the collected signatures
//          name : channelName, // the channel name
//          orderer : orderer,
//          txId  : tx_id //the generated transaction id
//        };
//
//        // this call will return a Promise
//        let response = await client.createChannel(request);
//        logger.info('Channel created - response: ' + util.inspect(response));
//
//    } catch (error) {
//        logger.error('Failed to createChannel: ' + error);
//        throw error;
//    }
}

// Creates a channel config update file that can be signed and used to update the channel config
async function addOrgToConsortium(args) {

    try {
        let channelName = args['channelname'];
        let org = args['org'];
        logger.info('Adding org: ' + org + ' to consortium defined in system channel: ' + channelName);

        await fetchLatestConfigBlock(channelName);
        await createNewOrgConfig(org);

        // Generate the new config for the org
        let scriptName = 'config-update-system-channel.sh';
        let localScriptPath = path.resolve(__dirname + "/scripts-for-api", scriptName);
        // Copy the file to the /opt/share/rca-scripts directory. This will make it available to the /scripts directory
        // inside the CLI container
        try {
            logger.info('Copying script file that will be executed: ' + localScriptPath + '. to: ' + scriptPath);
            fs.copyFileSync(localScriptPath, path.join(scriptPath, "new-org-comfig.sh"));
        } catch (error) {
            logger.error('Failed to copy the script file: ' + error);
            throw error;
        }

        let cmd = "kubectl exec -it $(kubectl get pod -l name=cli -o jsonpath=\"{.items[0].metadata.name}\" -n org0) -n org0 -- bash -c \"bash /scripts/" + scriptName + " " + channelName + " " + org + "\"";

        logger.info('Executing cmd: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Error during exec - failed to add org to consortium defined in system channel: ' + channelName);
            logger.error(err);
            logger.info(`stdout: ${stdout}`);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"Added org to consortium defined in system channel: " + channelName}
    } catch (error) {
        logger.error('Failed to add org to consortium defined in system channel: ' + error);
        throw error;
    }
}

// Creates a config for the new org using configtxgen
async function createNewOrgConfig(args) {

    try {
        let org = args['org'];
        logger.info('Creating a new config for org: ' + org);

        // Generate the new config for the org
        let scriptName = 'new-org-comfig.sh';
        let localScriptPath = path.resolve(__dirname + "/scripts-for-api", scriptName);
        // Copy the file to the /opt/share/rca-scripts directory. This will make it available to the /scripts directory
        // inside the CLI container
        try {
            logger.info('Copying script file that will be executed: ' + localScriptPath + '. to: ' + scriptPath);
            fs.copyFileSync(localScriptPath, path.join(scriptPath, "new-org-comfig.sh"));
        } catch (error) {
            logger.error('Failed to copy the script file: ' + error);
            throw error;
        }

        let cmd = "kubectl exec -it $(kubectl get pod -l name=cli -o jsonpath=\"{.items[0].metadata.name}\" -n org0) -n org0 -- bash -c \"bash /scripts/" + scriptName + " " + channelName + " " + org + "\"";

        logger.info('Executing cmd: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Error during exec - failed to create config for org: ' + org);
            logger.error(err);
            logger.info(`stdout: ${stdout}`);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"Created new config for org: " + org}
    } catch (error) {
        logger.error('Failed to create new config for org: ' + error);
        throw error;
    }
}

// Gets the latest config block from a channel
async function fetchLatestConfigBlock(args) {

    try {
        let channelName = args['channelname'];
        logger.info('Getting latest config block from channel: ' + channelName);

        let scriptName = 'fetch-config-block.sh';
        let localScriptPath = path.resolve(__dirname + "/scripts-for-api", scriptName);
        // Copy the file to the /opt/share/rca-scripts directory. This will make it available to the /scripts directory
        // inside the CLI container
        try {
            logger.info('Copying script file that will be executed: ' + localScriptPath + '. to: ' + scriptPath);
            fs.copyFileSync(localScriptPath, path.join(scriptPath, scriptName));
        } catch (error) {
            logger.error('Failed to copy the script file: ' + error);
            throw error;
        }

        let cmd = "kubectl exec -it $(kubectl get pod -l name=cli -o jsonpath=\"{.items[0].metadata.name}\" -n org0) -n org0 -- bash -c \"bash /scripts/" + scriptName + " " + channelName + "\"";

        logger.info('Executing cmd: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Error during exec - failed to create channel: ' + channelName);
            logger.error(err);
            logger.info(`stdout: ${stdout}`);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"Created new channel: " + channelName}
    } catch (error) {
        logger.error('Failed to create channel: ' + error);
        throw error;
    }
}

// This will prepare the environment for a new org: create directories, start K8s persistent volumes, etc.
async function setupOrg(args) {

    let org = args['org'];
    logger.info('Preparing environment for org: ' + org);
    let scriptName = 'scripts-for-api/setup-org.sh';
    let cmd = path.resolve(__dirname, scriptName);

    try {
        logger.info('Running command: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Failed to prepare environment');
            logger.error(err);
            logger.info(`stdout: ${stdout}`);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"Org setup. New org is: " + org}
    } catch (error) {
        logger.error('Failed to prepare environment: ' + error);
        throw error;
    }
}

// This will start a root and intermediate CA
async function startCA(args) {

    let org = args['org'];
    logger.info('Starting CAs');
    let scriptName = 'scripts-for-api/start-ca.sh';
    let cmd = path.resolve(__dirname, scriptName);

    try {
        logger.info('Running command: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Failed to start CA');
            logger.error(err);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"CA started "}
    } catch (error) {
        logger.error('Failed to start CA: ' + error);
    }
}

// This will register the new org
async function startRegisterOrg(args) {

    let org = args['org'];
    logger.info('Starting to register org: ' + org);
    let scriptName = 'scripts-for-api/start-register-org.sh';
    let cmd = path.resolve(__dirname, scriptName);

    try {
        logger.info('Running command: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Failed to register org');
            logger.error(err);
            logger.info(`stderr: ${stderr}`);
            return;
        }

        // the *entire* stdout and stderr (buffered)
        logger.info(`stdout: ${stdout}`);
        logger.info(`stderr: ${stderr}`);
        });
        return {"status":200,"message":"register org started "}
    } catch (error) {
        logger.error('Failed to register org: ' + error);
    }
}

exports.enrollAdmin = enrollAdmin;
exports.adminGateway = adminGateway;
exports.listNetwork = listNetwork;
exports.loadConfigtx = loadConfigtx;
exports.addOrg = addOrg;
exports.setupOrg = setupOrg;
exports.getOrgsFromConfigtx = getOrgsFromConfigtx;
exports.getProfilesFromConfigtx = getProfilesFromConfigtx;
exports.addConfigtxProfile = addConfigtxProfile;
exports.createTransactionConfig = createTransactionConfig;
exports.createChannel = createChannel;
exports.startCA = startCA;
exports.startRegisterOrg = startRegisterOrg;
exports.addOrgToConsortium = addOrgToConsortium;