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
const walletPath = path.join(process.cwd(), 'wallet');
const wallet = new FileSystemWallet(walletPath);
const gateway = new Gateway();
const { exec } = require('child_process');

let configtx = '';

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

//        let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));
        let ccp = yaml.parse(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));

        // Set connection options; identity and wallet
        let connectionOptions = {
          identity: 'admin',
          wallet: wallet,
          discovery: { enabled:true, asLocalhost:false }
        };

        // Connect to gateway using application specified parameters
        logger.info('Connecting to Fabric gateway.');

        await gateway.connect(ccp, connectionOptions);

}

async function listNetwork() {

    logger.info('Printing out the Fabric network');
    let client = gateway.getClient();
    logger.info('Client: ' + util.inspect(client));
    logger.info('ClientConfig: ' + util.inspect(client.getClientConfig()));
    let msp = client.getMspid();
    logger.info('msp: ' + util.inspect(msp));
    let peers = client.getPeersForOrg();
    logger.info('peers: ' + util.inspect(peers));

}

async function loadConfigtx(configtxPath) {

    try {
        logger.info('Loading the Fabric configtx.yaml at path: ' + configtxPath);
        configtx = yaml.safeLoad(fs.readFileSync(configtxPath, 'utf8'));
//        configtx = yaml.parse(fs.readFileSync(configtxPath, 'utf8'));
        logger.info('Configtx loaded at path: ' + configtxPath);
    } catch (error) {
        logger.error('Failed to loadConfigtx: ' + error);
        throw error;
    }

}

async function backupConfigtx(configtxPath) {

    try {
        // Backup the original configtx.yaml
        let filename = configtxPath + Math.floor(Date.now() / 1000);
        logger.info('Backing up original configtx.yaml at path: ' + configtxPath + '. Backup file titled: ' + filename);
        fs.copyFileSync(configtxPath, filename);
    } catch (error) {
        logger.error('Failed to backup Configtx: ' + error);
        throw error;
    }
}


async function getOrgs(configtxPath) {

    let orgs = [];
    try {
        await loadConfigtx(configtxPath);
        for (let org in configtx['Organizations']) {
            logger.info("Orgs in this network are: " + configtx['Organizations'][org]['Name'] + ' with MSP ' + configtx['Organizations'][org]['ID']);
            orgs.push(configtx['Organizations'][org]['Name']);
        }
        return orgs;
    } catch (error) {
        logger.error('Failed to getOrgs: ' + error);
        throw error;
    }
}


async function getProfiles(configtxPath) {

    let profiles = [];
    try {
        await loadConfigtx(configtxPath);
        logger.info("Profiles in this network are: " + Object.keys(configtx['Profiles']))
        for (let profile in configtx['Profiles']) {
            logger.info("Profiles in this network are: " + profile);
            profiles.push(configtx['Profiles'][profile]);
        }
        return profiles;
    } catch (error) {
        logger.error('Failed to getProfiles: ' + error);
        throw error;
    }
}


// This will create a new org in configtx.yaml, by copying an existing org
//
// TODO: the anchor peer needs to be passed to this function, and updated into configtx.yaml
async function addOrg(configtxPath, args) {

    let org = args['org'];
    try {
        let orgsInConfig = await getOrgs(configtxPath);
        //Check that the new org to be added does not already exist in configtx.yaml
        if (orgsInConfig.indexOf(org) > -1) {
            logger.error('Org: ' + org + ' already exists in configtx.yaml. These orgs are already present: ' + orgsInConfig);
            return;
        }
        await backupConfigtx(configtxPath);

        // Use the template to add a new org to configtx.yaml
        let contents = "";
        fs.readFileSync(configtxPath).toString().split('\n').forEach(function (line) {
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
        fs.writeFileSync(configtxPath, contents);
        logger.info('Added a new org to configtx.yaml at path: ' + configtxPath);

//        let neworg = JSON.parse(JSON.stringify(configtx['Organizations'][1]));
//        let orgname = neworg['Name'];
//        let mspdir = neworg['MSPDir'];
//        logger.info("Neworg: " + util.inspect(neworg));
//        neworg['Name'] = org;
//        neworg['ID'] = org + 'MSP';
//        neworg['MSPDir'] = mspdir.replace(orgname, org);
//        neworg['Policies']['Readers']['Rule'] = neworg['Policies']['Readers']['Rule'].replace(orgname, org);
//        neworg['Policies']['Writers']['Rule'] = neworg['Policies']['Writers']['Rule'].replace(orgname, org);
//        neworg['Policies']['Admins']['Rule'] = neworg['Policies']['Admins']['Rule'].replace(orgname, org);
//        logger.info("Neworg: " + util.inspect(neworg));
//        configtx['Organizations'].push(neworg);
//        logger.info('Configtx updated with org: ' + util.inspect(configtx));
//        saveConfigtx(configtxPath);
        return {"status":200,"message":"Org added to configtx.yaml: " + org}
    } catch (error) {
        logger.error('Failed to addOrg: ' + error);
    }
}


// This will create a new profile in configtx.yaml, which can be used for creating new channels
// I have tried to edit this file using the js-yaml, yaml libraries. Neither of them support anchors in YAML, so
// the resulting YAML is written incorrectly and cannot be processed by configtxgen. I've therefore taken to
// manually reading and writing the file, without using YAML
async function addConfigtxProfile(configtxPath, args) {

    let profileName = args['profilename'];
    let orgs = args['orgs'];
    try {
        let profilesInConfig = await getProfiles(configtxPath);
        //Check that the new profile to be added does not already exist in configtx.yaml
        if (profilesInConfig.indexOf(profileName) > -1) {
            logger.error('Profile: ' + profileName + ' already exists in configtx.yaml. These profiles are already present: ' + profilesInConfig);
            return;
        }
        await backupConfigtx(configtxPath);
        let fd;

        // Use the template to add a new profile to configtx.yaml
        try {
                fs.readFile('./templates/profile.yaml', 'utf8', function(err, data) {
                    if (err) throw err;
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
                    fd = fs.openSync(configtxPath, 'a');
                    fs.appendFileSync(fd, result, 'utf8');
                    logger.info('Appending a new profile to configtx.yaml: ' + result);

                });
        } catch (err) {
            logger.error('Failed to addConfigtxProfile: ' + error);
        } finally {
            if (fd !== undefined)
                fs.closeSync(fd);
        }

        logger.info('Appended a new profile to configtx.yaml at path: ' + configtxPath);

//        let orgsInConfig = await getOrgs(configtxPath);
//        logger.info('addConfigtxProfile orgs already in config: ' + util.inspect(orgsInConfig));
//        //Check that the orgs to be added to the profile already exist in configtx.yaml
//        for (let org of orgs) {
//            logger.info('addConfigtxProfile checking whether org exists: ' + util.inspect(org));
//            if (orgsInConfig.indexOf(org) < 0) {
//                logger.error('Org: ' + org + ' does not exist in configtx.yaml. It cannot be added to a profile');
//                return;
//            }
//        }
//        //Copy an existing profile. We use the 2nd profile because the first belongs to the orderer
//        let newprofile = JSON.parse(JSON.stringify(configtx['Profiles']['OrgsChannel']));
//        logger.info('addConfigtxProfile - newprofile is: ' + util.inspect(newprofile));
//        newprofile['Application']['Organizations'] = orgs;
//        configtx['Profiles'][profileName] = newprofile;
//        logger.info('Configtx updated with profile: ' + util.inspect(configtx));
//        saveConfigtx(configtxPath);
        return {"status":200,"message":"Profile added to configtx.yaml: " + profileName}
    } catch (error) {
        logger.error('Failed to addConfigtxProfile: ' + error);
    }
}

// This will generate a new transaction config, used to create a new channel
async function createTransactionConfig(configtxPath, args) {

    let profileName = args['profilename'];
    let channelName = args['channelname'];
    let configtxPathDir = path.dirname(configtxPath);
    let cmd = "cd " + configtxPathDir + "; configtxgen -profile " + profileName + " -outputCreateChannelTx " + channelName + ".tx -channelID " + channelName;
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
    } catch (error) {
        logger.error('Failed to createTransactionConfig: ' + error);
    }
}

exports.enrollAdmin = enrollAdmin;
exports.adminGateway = adminGateway;
exports.listNetwork = listNetwork;
exports.loadConfigtx = loadConfigtx;
exports.addOrg = addOrg;
exports.getOrgs = getOrgs;
exports.getProfiles = getProfiles;
exports.addConfigtxProfile = addConfigtxProfile;
exports.createTransactionConfig = createTransactionConfig;