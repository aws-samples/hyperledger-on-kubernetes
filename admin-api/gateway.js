'use strict';

const FabricCAServices = require('fabric-ca-client');
const { FileSystemWallet, X509WalletMixin } = require('fabric-network');
const fs = require('fs');
const path = require('path');

async function main() {
    try {

        let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));

        // Create a new CA client for interacting with the CA.
        const caURL = ccp.certificateAuthorities['ca-org1'].url;
        const ca = new FabricCAServices(caURL);

        // Create a new file system based wallet for managing identities.
        const walletPath = path.join(process.cwd(), 'wallet');
        const wallet = new FileSystemWallet(walletPath);
        console.log(`Wallet path: ${walletPath}`);

        // Check to see if we've already enrolled the admin user.
        const adminExists = await wallet.exists('admin');
        if (adminExists) {
            console.log('An identity for the admin user "admin" already exists in the wallet');
            return;
        }

        // Enroll the admin user, and import the new identity into the wallet.
        const enrollment = await ca.enroll({ enrollmentID: ccp.certificateAuthorities['ca-org1'].registrar.enrollId, enrollmentSecret: ccp.certificateAuthorities['ca-org1'].registrar.enrollSecret });
        const identity = X509WalletMixin.createIdentity('org1MSP', enrollment.certificate, enrollment.key.toBytes());
        wallet.import('admin', identity);
        console.log('Successfully enrolled admin user "admin" and imported it into the wallet');

        // Set connection options; identity and wallet
        let connectionOptions = {
          identity: 'admin',
          wallet: wallet,
          discovery: { enabled:true }
        };

        // Connect to gateway using application specified parameters
        console.log('Connect to Fabric gateway.');
        const gateway = new Gateway();

        await gateway.connect(connectionProfile, connectionOptions);

    } catch (error) {
        console.error(`Failed to enroll admin user "admin": ${error}`);
        process.exit(1);
    }
}

main();