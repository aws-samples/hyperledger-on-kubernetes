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
const gateway = new Gateway();
const { exec } = require('child_process');
const { execSync } = require('child_process');
const { execFile } = require('child_process');
// This is a useful little library. It loads the file env.sh as a list of properties so that I can easily refer to a property in the code
// See loadEnv()
const dotenv = require('dotenv')

var CONFIG = require('./config.json');

let configtxContents = '';
let envConfigContents = '';
let dataPath = CONFIG.datapath;
let configtxFilename = CONFIG.configtxfile;
let scriptPath = CONFIG.scriptpath;
let envFilename = CONFIG.envfile;
let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));
let client;

// this is the default name given to the orderer system channel when booting the Fabric network
// unless you have overridden this
let systemChannelName = 'testchainid';

// command line to execute a script/command inside the CLI container
let cliCommand = "kubectl exec -i $(kubectl get pod -l name=cli -o jsonpath=\"{.items[0].metadata.name}\" -n org0) -n org0 -- bash -c ";

/************************************************************************************
 * Enroll an admin user. The admin user will either be obtained from the Fabric wallet
 * or from the CA for this organisation
 ************************************************************************************/

async function enrollAdminForOrg(args) {
    try {
        let org = args['org'];
        logger.info('Enrolling admin for org: ' + org);
        const walletPath = path.join(process.cwd(), 'wallet-' + org);
        const wallet = new FileSystemWallet(walletPath);
        // Check to see if we've already enrolled the admin user.
        const adminExists = await wallet.exists('admin');
        if (adminExists) {
            logger.info('An identity for the admin user "admin" already exists in the wallet for org: ' + org);
            logger.info('Wallet identities: ' + util.inspect(await wallet.list()));
            logger.info('Wallet admin exists: ' + util.inspect(await wallet.exists('admin')));
            return {"status":200,"message":"Admin user enrolled and set to the current user"};
        }

        // Create a new CA client for interacting with the CA.
        const caURL = ccp.certificateAuthorities['ca-' + org].url;
        logger.info('CA URL: ' + caURL);
        const ca = new FabricCAServices(caURL);

        // Enroll the admin user, and import the new identity into the wallet.
        const enrollment = await ca.enroll({ enrollmentID: ccp.certificateAuthorities['ca-' + org].registrar[0].enrollId, enrollmentSecret: ccp.certificateAuthorities['ca-' + org].registrar[0].enrollSecret });
        const identity = X509WalletMixin.createIdentity(org + 'MSP', enrollment.certificate, enrollment.key.toBytes());
        logger.info(`Wallet path: ${walletPath}`);
        await wallet.import('admin', identity);
        logger.info('Successfully enrolled admin user "admin" and imported it into the wallet');
        logger.info('Wallet identities: ' + util.inspect(await wallet.list()));
        logger.info('Wallet admin exists: ' + util.inspect(await wallet.exists('admin')));
        return {"status":200,"message":"Admin user enrolled and set to the current user for org: " + org};
    } catch (error) {
        logger.error(`Failed to enroll admin user "admin": ${error}`);
        throw error;
    }
}

/************************************************************************************
 * Get the list of users enrolled with the CA for the provided org
 ************************************************************************************/

async function getUsersForOrg(args) {
    try {
        let org = args['org'];
        logger.info('Getting the users enrolled for org: ' + org);

        let client = await connection.getClientForOrg(org, "admin-org1");
        logger.info('Fabric getUserContext: ' + util.inspect(client.getUserContext()));
        // Get the list of users
        let users = await ca.newIdentityService().getAll(new User(client.getUserContext()));
        logger.info('Users enrolled with CA are: ' + util.inspect(users));

        await enrollAdminForOrg(args);

        const walletPath = path.join(process.cwd(), 'wallet-' + org);
        const wallet = new FileSystemWallet(walletPath);
        const walletList = await wallet.list();
        logger.info('Wallet at path: ' +  path.join(process.cwd(), 'wallet-' + org) + ' contains: ' + util.inspect(walletList));

        // Create a new CA client for interacting with the CA.
        const caURL = ccp.certificateAuthorities['ca-' + org].url;
        logger.info('CA URL: ' + caURL);
        const ca = new FabricCAServices(caURL);
        logger.info('Fabric CA Name: ' + util.inspect(ca.getCaName()));

        return {"status":200,"message":"Admin user enrolled and set to the current user"};
    } catch (error) {
        logger.error(`Failed to get users for org: ${error}`);
        throw error;
    }
}

/************************************************************************************
 * Set a Fabric client that uses the admin identity
 ************************************************************************************/

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

/************************************************************************************
 * Print out the Fabric network configuration as seen by the current Fabric client object
 ************************************************************************************/

async function listNetwork() {

    logger.info('Printing out the Fabric network');
    logger.info('Client: ' + util.inspect(client));
    logger.info('ClientConfig: ' + util.inspect(client.getClientConfig()));
    let msp = client.getMspid();
    logger.info('msp: ' + util.inspect(msp));
    let peers = client.getPeersForOrg();
    logger.info('peers: ' + util.inspect(peers));

}

/************************************************************************************
 * Install chaincode on all peers belonging to an org
 ************************************************************************************/

async function installChaincode(args) {

    try {
        let channelName = args['channelname'];
        let chaincodeName = args['chaincodename'];
        let chaincodeVersion = args['chaincodeversion'];
        let chaincodeLanguage = args['chaincodelanguage'];
        let org = args['org'];
        logger.info('Installing chaincode name: ' + chaincodeName + ' version: ' + chaincodeVersion + ' on all peers in org: ' + org);
        let scriptName = 'install-chaincode.sh';
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
        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + chaincodeName + " " + chaincodeVersion + " " + chaincodeLanguage + " " + org + " " + channelName + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Installed chaincode name: " + chaincodeName + ' version: ' + chaincodeVersion + ' on all peers in org: ' + org};
    } catch (error) {
        logger.error('Failed to install chaincode: ' + error);
        throw error;
    }

//    try {
//
//        let channelName = args['channelName'];
//        let chaincodeName = args['chaincodeName'];
//
//        logger.info("Installing chaincode: " + chaincodeName + " on peers joined to channel: " + channelName);
//    //
//    //    let response = await gateway.enrollAdmin();
//    //    await gateway.adminGateway();
//
//        let user = {"username":"michael","org":"org1"};
//        let response = await connection.getRegisteredUser(user, true);
//        logger.info("getRegisteredUser response: " + util.inspect(response));
//
//        // client.loadFromConfig('connection-profile/org1/client-org1.yaml');
//        let clientLocal = await connection.getClientForOrg("org1","michael");
//        logger.info("clientLocal response: " + util.inspect(clientLocal));
//
//        logger.info("about to getPeer");
//        let peer = clientLocal.getPeer("peer1-org1.org1");
//        logger.info("getPeer: " + util.inspect(peer));
//
////        logger.info("getChannel: " + util.inspect(clientLocal.getChannel()));
//
////        const network = await gateway.getNetwork('mychannel');
////        logger.info('network: ' + util.inspect(network));
////        const channel = network.getChannel();
////        logger.info('channel: ' + util.inspect(channel));
////        const contract = network.getContract(chaincodeName);
////        logger.info('contract: ' + util.inspect(contract));
//    } catch (error) {
//        logger.error('Failed to installChaincode: ' + error);
//        throw error;
//    }

}

/************************************************************************************
 * Install chaincode on all peers belonging to an org
 ************************************************************************************/

async function instantiateChaincode(args) {

    try {
        let channelName = args['channelname'];
        let chaincodeName = args['chaincodename'];
        let chaincodeVersion = args['chaincodeversion'];
        let chaincodeInit = args['chaincodeinit'];
        let orgs = args['orgs'];
        logger.info('Instantiating chaincode name: ' + chaincodeName + ' version: ' + chaincodeVersion + ' on peer in orgs: ' + orgs);
        let scriptName = 'instantiate-chaincode.sh';
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
        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + chaincodeName + " " + chaincodeVersion + " " + chaincodeInit + " " + orgs + " " + channelName + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Instantiated chaincode name: " + chaincodeName + ' version: ' + chaincodeVersion + ' on peer in orgs: ' + orgs};
    } catch (error) {
        logger.error('Failed to instantiate chaincode: ' + error);
        throw error;
    }
}
/************************************************************************************
 * Add a new organisation to the Fabric network. This will do a number of things:
 *      Adds the org to configtx.yaml
 *      Adds the org to the env.sh file that is used to configure the Fabric network
 *      Adds the org to the consortium defined in the profiles section in configtx.yaml
 *      Updates the system channel configuration block with the new consortium profile
 ************************************************************************************/

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
            await addOrgToConfigtx({"org": org});
        }

        let orgsInEnv = await getOrgsFromEnv();
        //Check that the new org to be added does not already exist in env.sh
        if (orgsInEnv.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in env.sh. These orgs are already present: ' + orgsInEnv);
        } else {
            await addOrgToEnv({"org": org});
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

///////////////////////////////////////////////////////////////////////////////
//////////////////////////////// UPDATE FABRIC CONFIG FILES ///////////////////
///////////////////////////////////////////////////////////////////////////////

// I have tried to edit configtx.yaml using the js-yaml, yaml libraries. Neither of them support anchors in YAML, so
// the resulting YAML is written incorrectly and cannot be processed by configtxgen. I've therefore taken to
// manually reading and writing the file, without using YAML

/************************************************************************************
 * This will create a new org in configtx.yaml, by copying an existing org from the
 * template in the file ./templates/org.yaml
 ************************************************************************************/

// TODO: the anchor peer needs to be passed to this function, and updated into configtx.yaml
async function addOrgToConfigtx(args) {

    try {
        let org = args['org'];
        let orgsInConfig = await getOrgsFromConfigtx();
        //Check that the new org to be added does not already exist in configtx.yaml
        if (orgsInConfig.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in configtx.yaml. These orgs are already present: ' + orgsInConfig);
            return ('Org: ' + org + ' already exists in configtx.yaml. These orgs are already present: ' + orgsInConfig);
        }
        let configtxFilepath = path.join(dataPath, configtxFilename);
        await backupFile(configtxFilepath);

        // Use the template to add a new org to configtx.yaml. The new org needs to be
        // added in two places:
        //      1) The Consortium definition, under Profiles, in Consortiums->SampleConsortium->Organizations
        //      2) The Organizations section
        let contents = "";
        let profilesBool = false;
        let consortiumsBool = false;
        let configtxSections = ["Capabilities","Organizations","Orderer","Channel","Application"];
        fs.readFileSync(configtxFilepath).toString().split('\n').forEach(function (line) {
            contents += line + "\n";

            // Add the new org to the Consortiums section. This is a bit tricky as there could be more than one
            // Consortiums section in configtx.yaml, though only one of them will be used to generate the orderer
            // genesis block. So I'll need to add the new org to all Consortiums

            // Reset my indicators that track where I am in the file, if I enter a new section in configtx.yaml
            for (let i = 0; i < configtxSections.length; i++) {
                let ix = line.toString().indexOf(configtxSections[i]);
                if (ix > -1 && ix < 2) {
                    profilesBool = false;
                    consortiumsBool = false;
                }
            }

            // Note when I have reached the Profiles section
            let ix = line.toString().indexOf("Profiles:");
            if (ix > -1 && ix < 2) {
                profilesBool = true;
            }
            if (profilesBool === true) {
                // Note when I have reached the Profiles->Consortiums section
                ix = line.toString().indexOf("Consortiums:");
                if (ix > -1) {
                    consortiumsBool = true;
                }
                if (consortiumsBool === true) {
                    // Add the new org when I have reached the Profiles->Consortiums->Organizations section
                    ix = line.toString().indexOf("Organizations:");
                    if (ix > -1) {
                        let newOrgLine = "                - *" + org;
                        contents += newOrgLine + "\n";
                        // Set to false. This will allow me to add the same org to different consortium definitions
                        consortiumsBool = false;
                    }
                }
            }
            ix = line.toString().indexOf("Organizations:");
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

/************************************************************************************
 * This will create a new org in env.sh
 ************************************************************************************/

async function addOrgToEnv(args) {

    try {
        let org = args['org'];
        let override;
        let orgsInEnv;
        if (args.hasOwnProperty('override')) {
            override = args['override'];
        }
        else {
            orgsInEnv = await getOrgsFromEnv();
            //Check that the new org to be added does not already exist in env.sh
            if (orgsInEnv.indexOf(org) > -1) {
                logger.error('Org: ' + org + ' already exists in env.sh. These orgs are already present: ' + orgsInEnv);
                return ('Org: ' + org + ' already exists in env.sh. These orgs are already present: ' + orgsInEnv);
            }
            orgsInEnv.push(org);
        }
        let envFilepath = path.join(scriptPath, envFilename);
        await backupFile(envFilepath);

        // Use the template to add a new org to env.sh
        let contents = "";
        fs.readFileSync(envFilepath).toString().split('\n').forEach(function (line) {
            let ix = line.toString().indexOf("PEER_ORGS=");
            if (ix > -1 && ix < 2) {
                logger.info('Found the PEER_ORGS section in env.sh - adding new org to this env variable');
                let result = '';
                if (override) {
                    result = 'PEER_ORGS="' + org + '"'
                }
                else {
                    result = 'PEER_ORGS="' + orgsInEnv.join(" ") + '"'
                }
                contents += result + "\n";
                logger.info('Updated PEER_ORGS in env.sh to:' + result);
            } else {
                ix = line.toString().indexOf("PEER_DOMAINS=");
                if (ix > -1 && ix < 2) {
                    logger.info('Found the PEER_DOMAINS section in env.sh - adding new org to this env variable');
                    let result = '';
                    if (override) {
                        result = 'PEER_DOMAINS="' + org + '"'
                    }
                    else {
                        result = 'PEER_DOMAINS="' + orgsInEnv.join(" ") + '"'
                    }
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

/************************************************************************************
 * This will create a new profile in configtx.yaml, by copying an existing profile from the
 * template in the file ./templates/profile.yaml. The profile can be used for
 * creating new channels.
 ************************************************************************************/

async function addProfileToConfigtx(args) {

    let profileName = args['profilename'];
    let orgs = args['orgs']; // orgs to be included in the profile
    try {
        let profilesInConfig = await getProfilesFromConfigtx();
        //Check that the new profile to be added does not already exist in configtx.yaml
        if (profilesInConfig.indexOf(profileName) > -1) {
            logger.error('Profile: ' + profileName + ' already exists in configtx.yaml. These profiles are already present: ' + profilesInConfig);
            return ('Profile: ' + profileName + ' already exists in configtx.yaml. These profiles are already present: ' + profilesInConfig);
        }
        let orgsInConfig = await getOrgsFromConfigtx();
        //Check that the orgs to be used in the profile already exist in configtx.yaml
        for (let org of orgs) {
            if (orgsInConfig.indexOf(org) < 0) {
                logger.error('Org: ' + org + ' does not exist in configtx.yaml - you cannot create a profile that uses this org. These orgs are already present: ' + orgsInConfig);
                return ('Org: ' + org + ' does not exist in configtx.yaml - you cannot create a profile that uses this org. These orgs are already present: ' + orgsInConfig);
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
            logger.error('Failed to addProfileToConfigtx: ' + error);
        } finally {
            if (fd !== undefined)
                fs.closeSync(fd);
        }

        logger.info('Appended a new profile to configtx.yaml at path: ' + dataPath);
        return {"status":200,"message":"Profile added to configtx.yaml: " + profileName}
    } catch (error) {
        logger.error('Failed to addProfileToConfigtx: ' + error);
        throw error;
    }
}

/************************************************************************************
 * This will generate a new channel transaction config, used to create a new channel. The
 * transaction config is generated by running configtxgen against configtx.yaml, and
 * specifying one of the profiles in configtx.yaml to use for the new channel config
 ************************************************************************************/

async function createTransactionConfig(args) {

    try {
        let profileName = args['profilename'];
        let channelName = args['channelname'];
        logger.info('Generating a transaction config for profile/channel: ' + util.inspect(args));
        if (!(profileName && channelName)) {
            logger.error('Both profileName and channelName must be provided to generate a transaction config');
            logger.error('Failed to createTransactionConfig');
        }
        let profilesInConfig = await getProfilesFromConfigtx();
        //Check that the new profile to be added does not already exist in configtx.yaml
        if (profilesInConfig.indexOf(profileName) < 0) {
            logger.error('Profile: ' + profileName + ' does not exist in configtx.yaml - cannot generate a transaction config. These profiles are already present: ' + profilesInConfig);
            return ('Profile: ' + profileName + ' does not exist in configtx.yaml - cannot generate a transaction config. These profiles are already present: ' + profilesInConfig);
        }
        let cmd = cliCommand + "\"cd /data; export FABRIC_CFG_PATH=/data; configtxgen -profile " + profileName + " -outputCreateChannelTx " + channelName + ".tx -channelID " + channelName + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Created channel configuration transaction file - Check ls -lt /opt/share/rca-data for the latest .tx file"}
    } catch (error) {
        logger.error('Failed to createTransactionConfig: ' + error);
    }
}

/************************************************************************************
 * This will create a new channel using a channel transaction config
 ************************************************************************************/

async function createChannel(args) {

    try {
        let channelName = args['channelname'];
        logger.info('Creating new channel: ' + channelName);
        let scriptName = 'create-channel.sh';
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

        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + channelName + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Created new channel: " + channelName + ". Check ls -lt /opt/share/rca-data for the latest .block file"};
    } catch (error) {
        logger.error('Failed to create channel: ' + error);
        throw error;
    }
}

/************************************************************************************
 * This will join peer nodes to a new channel
 ************************************************************************************/

async function joinChannel(args) {

    try {
        let channelName = args['channelname'];
        let orgs = args['orgs'];
        logger.info('Joining peers to new channel: ' + channelName + " for orgs: " + orgs);
        let scriptName = 'join-channel.sh';
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
        for (let org of orgs) {
            logger.info('Joining peer for org: ' + org + ' to new channel: ' + channelName);
            let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + channelName + " " + org + "\"";
            await execCmd(cmd);
        }
        return {"status":200,"message":"Joined orgs: " + orgs + " to new channel: " + channelName};
    } catch (error) {
        logger.error('Failed to join channel: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Adds a new org to the consortium defined in the system channel
 ************************************************************************************/

async function addOrgToConsortium(args) {

    try {
        let channelName = args['channelname'];
        let org = args['org'];
        logger.info('Adding org: ' + org + ' to consortium defined in system channel: ' + channelName);

        await fetchLatestConfigBlock({"channelname": channelName, "systemchannel": true});
        await createNewOrgConfig({"org": org});
        await createChannelConfigUpdate({"org": org, "channelname": channelName, "systemchannel": true});
        await applyChannelConfigUpdate({"org": org, "channelname": channelName, "systemchannel": true});

        return {"status":200,"message":"Added org to consortium defined in system channel: " + channelName}
    } catch (error) {
        logger.error('Failed to add org to consortium defined in system channel: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Gets the latest config block from a channel
 ************************************************************************************/

async function fetchLatestConfigBlock(args) {

    try {
        let channelName = args['channelname'];
        let systemChannel = args['systemchannel'];
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

        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + channelName + " " + systemChannel + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Got latest config block from channel: " + channelName}
    } catch (error) {
        logger.error('Failed to get latest config block from channel: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Creates a config for the new org using configtxgen
 ************************************************************************************/

async function createNewOrgConfig(args) {

    try {
        let org = args['org'];
        logger.info('Creating a new config for org: ' + org);

        // Generate the new config for the org
        let scriptName = 'new-org-config.sh';
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

        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + org + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Created new config for org: " + org}
    } catch (error) {
        logger.error('Failed to create new config for org: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Creates an update config by performing a 'diff' between the existing channel config
 * and the config generated in createNewOrgConfig. This update config can then be
 * applied to the channel to update the channel config.
 ************************************************************************************/

async function createChannelConfigUpdate(args) {

    try {
        let org = args['org'];
        let channelName = args['channelname'];
        let systemChannel = args['systemchannel'];
        logger.info('Creating a channel update config for org: ' + org + ", channel: " + channelName);

        // Generate the update config for the org
        let scriptName = 'create-channel-config-update.sh';
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

        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + channelName + " " + org + " " + systemChannel + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Created new channel update config for org: " + org}
    } catch (error) {
        logger.error('Failed to create new channel update config for org: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Applies the channel config update envelope to the channel. This will create a new
 * transaction config block on the channel.
 ************************************************************************************/

async function applyChannelConfigUpdate(args) {

    try {
        let org = args['org'];
        let channelName = args['channelname'];
        let systemChannel = args['systemchannel'];
        logger.info('Apply a channel update config for org: ' + org + ", channel: " + channelName);

        // Generate the update config for the org
        let scriptName = 'update-channel-config.sh';
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

        let cmd = cliCommand + "\"bash /scripts/" + scriptName + " " + channelName + " " + org + " " + systemChannel + "\"";

        await execCmd(cmd);
        return {"status":200,"message":"Applied new channel update config for org: " + org}
    } catch (error) {
        logger.error('Failed to apply new channel update config for org: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Prepare the Kubernetes environment for a new org:
 *      Creates a new namespace in the EKS cluster for the org
 *      Creates the necessary directory structure for the new org's MSP
 *      Creates the EKS PV & PVCs (persistent volumes), mapping to the new org's MSP
 ************************************************************************************/

async function setupOrg(args) {

    let org = args['org'];
    logger.info('Preparing environment for org: ' + org);
    let scriptName = 'setup-org.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"Org setup. New org is: " + org}
}

/************************************************************************************
 * This will start a root and intermediate CA for the new org. These will run in
 * Kubernetes pods in EKS
 ************************************************************************************/

async function startCA(args) {

    let org = args['org'];
    logger.info('Starting CAs');
    let scriptName = 'start-ca.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"CA started "}
}

/************************************************************************************
 * This will register the new org. Registration creates an identity for the new org.
 * Registration will run in a Kubernetes pod in EKS
 ************************************************************************************/

async function startRegisterOrg(args) {

    let org = args['org'];
    logger.info('Starting to register org: ' + org);
    let scriptName = 'start-register-org.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"register org started "}
}

/************************************************************************************
 * This will register the new peer. Registration creates an identity for the new peer.
 * Registration will run in a Kubernetes pod in EKS
 ************************************************************************************/

async function startRegisterPeer(args) {

    let org = args['org'];
    logger.info('Starting to register peer for org: ' + org);
    let scriptName = 'start-register-peer.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"register peer started "}
}

/************************************************************************************
 * This will start the new peer. Starting the peer also creates the MSP for the peer.
 ************************************************************************************/

async function startPeer(args) {

    let org = args['org'];
    logger.info('Starting the peers for org: ' + org);
    let scriptName = 'start-peers.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"Peer started "}
}

/************************************************************************************
 * Prepare the Kubernetes environment for a new remote org:
 *      Creates a new namespace in the EKS cluster for the org
 *      Creates the necessary directory structure for the new org's MSP
 *      Creates the EKS PV & PVCs (persistent volumes), mapping to the new org's MSP
 ************************************************************************************/

async function setupRemoteOrg(args) {

    let org = args['org'];
    logger.info('Preparing environment for remote org: ' + org);
    let scriptName = 'copy-scripts.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    // Add the org to env.sh. In this case we will overwrite any other orgs in the file
    await addOrgToEnv({"org": org, "override": true});

    scriptName = 'setup-remote-org.sh';
    cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"Remote org setup. New org is: " + org}
}

/************************************************************************************
 * This will start a new peer in a remote AWS account, separate from the account that
 * hosts the main Fabric orderer.
 ************************************************************************************/

async function startRemotePeer(args) {

    let org = args['org'];
    logger.info('Starting the remote peers for org: ' + org);
    let scriptName = 'start-remote-peer.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"Remote peer started "}
}

/************************************************************************************
 * This will start all the components in a new Fabric network. After creating the EKS
 * cluster and deploying this API server, this function should be called via the API.
 * It carries out the same tasks as ./fabric-main/start-fabric.sh.
 ************************************************************************************/

async function startFabricNetwork(args) {

    logger.info('Starting the Fabric network');
    let scriptName = 'start-fabric.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"Fabric network started "}
}

/************************************************************************************
 * This will stop all the components in a new Fabric network.
 * It carries out the same tasks as ./fabric-main/stop-fabric.sh.
 ************************************************************************************/

async function stopFabricNetwork(args) {

    logger.info('Stopping the Fabric network');
    let scriptName = 'stop-fabric.sh';
    let cmd = path.resolve(__dirname + "/scripts-for-api", scriptName);

    await execCmd(cmd);
    return {"status":200,"message":"Fabric network stopped "}
}

///////////////////////////////////////////////////////////////////////////////
//////////////////////////////// MANAGE FABRIC CONFIG FILES ///////////////////
///////////////////////////////////////////////////////////////////////////////

/************************************************************************************
 * Loads configtx.yaml into a Javascript object for easy querying
 ************************************************************************************/

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


/************************************************************************************
 * Loads env.sh into ENV variables for easy querying
 ************************************************************************************/

async function loadEnv() {

    try {
        require('dotenv').config({ path: path.join(scriptPath, envFilename) })
        logger.info('Loading the Fabric env.sh at path: ' + path.join(scriptPath, envFilename));
        envConfigContents = dotenv.parse(fs.readFileSync(path.join(scriptPath, envFilename)))
        logger.info('Env.sh loaded at path: ' + path.join(scriptPath, envFilename));
    } catch (error) {
        logger.error('Failed to loadEnv: ' + error);
        throw error;
    }

}

/************************************************************************************
 * Backup a file. Used to backup config files before updating them
 ************************************************************************************/

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

/************************************************************************************
 * Get the list of organisations that are configured in configtx.yaml
 ************************************************************************************/

async function getOrgsFromEnv() {

    try {
        await loadEnv();
        let orgString = envConfigContents.PEER_ORGS;
        let orgArray = orgString.split(" ");
        logger.info("Orgs in env.sh for this network are: " + orgString);
        return orgArray;
    } catch (error) {
        logger.error('Failed to getOrgsFromEnv: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Get the list of organisations that are configured in configtx.yaml
 ************************************************************************************/

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

/************************************************************************************
 * Get the list of profiles that are configured in configtx.yaml
 ************************************************************************************/

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

/************************************************************************************
 * Get the list of ports that have been assigned to peers, orderers, ca's. These are
 * stored in files, in the SCRIPTS directory
 ************************************************************************************/

async function getPorts(args) {

    try {
        let portType = args['portType'];
        let portFile;
        let data = {};
        switch (portType) {
          case "orderer":
             portFile = path.join(scriptPath, "orderer-ports.sh");
             break;
          case "peer":
             portFile = path.join(scriptPath, "peer-ports.sh");
             break;
          case "rca":
             portFile = path.join(scriptPath, "rca-ports.sh");
             break;
          case "ica":
             portFile = path.join(scriptPath, "ica-ports.sh");
             break;
        }
        if (fs.existsSync(portFile)) {
            logger.info("Loading the ports used from file: " + portFile);
            data = fs.readFileSync (portFile, 'utf8');
            logger.info("Ports assigned to " + portType + " for this network are: " + data);
        }
        else {
            logger.info("No ports assigned to " + portType + " yet");
        }
        return data;
    } catch (error) {
        logger.error('Failed to getPorts: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Copy the MSP for an org to S3. This will allow the other org to download the MSP
 * and start a CA and peer node in another AWS account
 ************************************************************************************/

async function uploadMSPtoS3(args) {

    try {
        let org = args['org'];
        let region = args['region'];
        let account = args['account'];
        let S3bucket = args['S3bucketname'];
        logger.info('Uploading MSP for org: ' + org + ", to S3 bucket: " + S3bucket + ", region: " + region + " account: " + account);

        let scriptName = 'copy-msp-to-S3.sh';
        let localScriptPath = path.resolve(__dirname + "/scripts-for-api", scriptName);
        let cmd = localScriptPath + " " + S3bucket + " " + region + " " + account + " " + org;

        await execCmd(cmd);
        return {"status":200,"message":"Copied MSP to S3 for org: " + org}
    } catch (error) {
        logger.error('Failed to copy MSP to S3 for org: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Download the MSP for an org from S3. This will allow the org to use the MSP
 * and start a CA and peer node in an AWS account
 ************************************************************************************/

async function downloadMSPfromS3(args) {

    try {
        let org = args['org'];
        let S3bucket = args['S3bucketname'];
        logger.info('Downloading MSP for org: ' + org + ", from S3 bucket: " + S3bucket);

        let scriptName = 'copy-msp-from-S3.sh';
        let localScriptPath = path.resolve(__dirname + "/scripts-for-api", scriptName);
        let cmd = localScriptPath + " " + S3bucket + " " + org;

        await execCmd(cmd);
        return {"status":200,"message":"Copied MSP from S3 for org: " + org}
    } catch (error) {
        logger.error('Failed to copy MSP from S3 for org: ' + error);
        throw error;
    }
}

/************************************************************************************
 * Helper function to execute a command on the command line
 ************************************************************************************/

async function execCmd(cmd) {
    logger.info('Executing cmd: ' + cmd);
    let response = '';
    // Needs to be sync as we need the output of this command for any subsequent steps
    try {
        let stdout = execSync(cmd, {stdio: 'inherit'});
        if (stdout == null) {
            logger.info('Output of execSync is null. Assume success');
            response = {"status":200,"message":"Exec command executed successfully"};
        }
        else {
            logger.info('Output of execSync is: ' + stdout.toString());
            response = {"status":200,"message":"Exec command executed successfully. Stdout is: " + stdout.toString()};
        }
    } catch (error) {
        logger.error('Error during execSync. Error object is: ' + util.inspect(error));
        throw error;
    }
    return response;
}

exports.enrollAdminForOrg = enrollAdminForOrg;
exports.getUsersForOrg = getUsersForOrg;
exports.adminGateway = adminGateway;
exports.listNetwork = listNetwork;
exports.loadConfigtx = loadConfigtx;
exports.addOrg = addOrg;
exports.setupOrg = setupOrg;
exports.setupRemoteOrg = setupRemoteOrg;
exports.getOrgsFromConfigtx = getOrgsFromConfigtx;
exports.getOrgsFromEnv = getOrgsFromEnv;
exports.getProfilesFromConfigtx = getProfilesFromConfigtx;
exports.addProfileToConfigtx = addProfileToConfigtx;
exports.createTransactionConfig = createTransactionConfig;
exports.createChannel = createChannel;
exports.joinChannel = joinChannel;
exports.startCA = startCA;
exports.startRegisterOrg = startRegisterOrg;
exports.startRegisterPeer = startRegisterPeer;
exports.startPeer = startPeer;
exports.startRemotePeer = startRemotePeer;
exports.startFabricNetwork = startFabricNetwork;
exports.stopFabricNetwork = stopFabricNetwork;
exports.addOrgToConsortium = addOrgToConsortium;
exports.addOrgToEnv = addOrgToEnv;
exports.getPorts = getPorts;
exports.installChaincode = installChaincode;
exports.instantiateChaincode = instantiateChaincode;
exports.uploadMSPtoS3 = uploadMSPtoS3;
exports.downloadMSPfromS3 = downloadMSPfromS3;