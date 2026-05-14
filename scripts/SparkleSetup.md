# Sparkle Keys

# 1. Generate the keypair (private goes to keychain, public prints to stdout)

`./generate_keys --account Issues`

## Create the keypair + export the private key in one go

`./generate_keys --account Issues -x issues-sparkle.key`

## Save the public key to a file

`./generate_keys --account Issues -p > issues-sparkle.pub`

Back up issues-sparkle.key (private) somewhere safe. issues-sparkle.pub is the value for SUPublicEDKey in your app's Info.plist.

On a new Mac, import the backed-up private key into the login keychain:

`./generate_keys --account Issues -f issues-sparkle.key`

Done. Repeat with a different --account name for each app.
