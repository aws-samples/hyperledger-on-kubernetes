'use strict';

const FabricCAServices = require('fabric-ca-client');
const Client = require('fabric-client');
const logger = Client.getLogger('gateway');
const { FileSystemWallet, Gateway, X509WalletMixin } = require('fabric-network');
const util = require('util')
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const walletPath = path.join(process.cwd(), 'wallet');
const wallet = new FileSystemWallet(walletPath);
const gateway = new Gateway();

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

        let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));

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
    let msp = client.getMspid();
    logger.info('msp: ' + + util.inspect(msp));
    let peers = client.getPeersForOrg(msp);
    logger.info('peers: ' + + util.inspect(peers));

}


exports.enrollAdmin = enrollAdmin;
exports.adminGateway = adminGateway;
exports.listNetwork = listNetwork;