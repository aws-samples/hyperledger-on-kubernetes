'use strict';

const FabricCAServices = require('fabric-ca-client');
const Client = require('fabric-client');
const logger = Client.getLogger('gw');
const { FileSystemWallet, Gateway, X509WalletMixin } = require('fabric-network');
const util = require('util')
const fs = require('fs');
const path = require('path');
//const yaml = require('js-yaml');
const yaml = require('yaml');
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
//        configtx = yaml.safeLoad(fs.readFileSync(configtxPath, 'utf8'));
        configtx = yaml.parse(fs.readFileSync(configtxPath, 'utf8'));
        logger.info('Configtx loaded: ' + util.inspect(configtx));
    } catch (error) {
        logger.error('Failed to loadConfigtx: ' + error);
    }

}

async function saveConfigtx(configtxPath) {

    try {
        logger.info('Saving the Fabric configtx.yaml at path: ' + configtxPath);
        logger.info('Backing up original configtx.yaml at path: ' + configtxPath);
        fs.copyFileSync(configtxPath, configtxPath + Math.floor(Date.now() / 1000));
        fs.writeFile(configtxPath, yaml.stringify(configtx), function(err) {
                if (err) throw err;
            });
//        fs.writeFile(configtxPath, yaml.safeDump(configtx, {"noRefs":"true"}), function(err) {
//                if (err) throw err;
//            });
        logger.info('Configtx saved: ' + util.inspect(configtx));
    } catch (error) {
        logger.error('Failed to saveConfigtx: ' + error);
    }
}


async function getOrgs(configtxPath) {

    let orgs = [];
    try {
        logger.info('Reading the Fabric configtx.yaml at path: ' + configtxPath);
        await loadConfigtx(configtxPath);
        for (let org in configtx['Organizations']) {
            console.log("Orgs in this network are: " + configtx['Organizations'][org]['Name'] + ' with MSP ' + configtx['Organizations'][org]['ID']);
            orgs.push(configtx['Organizations'][org]['Name']);
        }
        return orgs;
    } catch (error) {
        logger.error('Failed to getOrgs: ' + error);
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
        //Copy an existing org. We use org1 because org0 is the orderer and has no anchor peers
        let neworg = JSON.parse(JSON.stringify(configtx['Organizations'][1]));
        let orgname = neworg['Name'];
        let mspdir = neworg['MSPDir'];
        console.log("Neworg: " + util.inspect(neworg));
        neworg['Name'] = org;
        neworg['ID'] = org + 'MSP';
        neworg['MSPDir'] = mspdir.replace(orgname, org);
        neworg['Policies']['Readers']['Rule'] = neworg['Policies']['Readers']['Rule'].replace(orgname, org);
        neworg['Policies']['Writers']['Rule'] = neworg['Policies']['Writers']['Rule'].replace(orgname, org);
        neworg['Policies']['Admins']['Rule'] = neworg['Policies']['Admins']['Rule'].replace(orgname, org);
        console.log("Neworg: " + util.inspect(neworg));
        configtx['Organizations'].push(neworg);
        logger.info('Configtx updated with org: ' + util.inspect(configtx));
        saveConfigtx(configtxPath);
        return {"status":200,"message":"Org added to configtx.yaml: " + org}
    } catch (error) {
        logger.error('Failed to addOrg: ' + error);
    }
}


// This will create a new profile in configtx.yaml, which can be used for creating new channels
async function addConfigtxProfile(configtxPath, args) {

    let profileName = args['profilename'];
    let orgs = args['orgs'];
    try {
        logger.info('addConfigtxProfile called with profile: ' + util.inspect(profileName) + ' orgs: ' + util.inspect(orgs));
        let orgsInConfig = await getOrgs(configtxPath);
        logger.info('addConfigtxProfile orgs already in config: ' + util.inspect(orgsInConfig));
        //Check that the orgs to be added to the profile already exist in configtx.yaml
        for (let org of orgs) {
            logger.info('addConfigtxProfile checking whether org exists: ' + util.inspect(org));
            if (orgsInConfig.indexOf(org) < 0) {
                logger.error('Org: ' + org + ' does not exist in configtx.yaml. It cannot be added to a profile');
                return;
            }
        }
        //Copy an existing profile. We use the 2nd profile because the first belongs to the orderer
        let newprofile = JSON.parse(JSON.stringify(configtx['Profiles']['OrgsChannel']));
        logger.info('addConfigtxProfile - newprofile is: ' + util.inspect(newprofile));
        newprofile['Application']['Organizations'] = orgs;
        configtx['Profiles'][profileName] = newprofile;
        logger.info('Configtx updated with profile: ' + util.inspect(configtx));
        saveConfigtx(configtxPath);
        return {"status":200,"message":"Profile added to configtx.yaml: " + profileName}
    } catch (error) {
        logger.error('Failed to addConfigtxProfile: ' + error);
    }
}

// This will generate a new transaction config, used to create a new channel
async function createTransactionConfig(configtxPath, args) {

    let profileName = args['profilename'];
    let channelName = args['channelname'];
    let cmd = "cd " + configtxPath + "; configtxgen -profile " + profileName + " -outputCreateChannelTx " + channelName + ".tx -channelID " + channelName;
    try {
        logger.info('Generating channel configuration: ' + cmd);
        exec(cmd, (err, stdout, stderr) => {
        if (err) {
            logger.error('Failed to generate channel configuration transaction');
            return;
        }

        // the *entire* stdout and stderr (buffered)
        console.log(`stdout: ${stdout}`);
        console.log(`stderr: ${stderr}`);
        });
    } catch (error) {
        logger.error('Failed to createTransactionConfig: ' + error);
    }
}

exports.enrollAdmin = enrollAdmin;
exports.adminGateway = adminGateway;
exports.listNetwork = listNetwork;
exports.loadConfigtx = loadConfigtx;
exports.saveConfigtx = saveConfigtx;
exports.addOrg = addOrg;
exports.getOrgs = getOrgs;
exports.addConfigtxProfile = addConfigtxProfile;
exports.createTransactionConfig = createTransactionConfig;