# COSMO Alpaca AL-Go Actions

This repository contains a set of GitHub actions used by the customized [COSMO Alpaca](https://cosmoconsult.com/cosmo-alpaca) AL-Go for GitHub templates.

Please go to https://aka.ms/AL-Go and [COSMO Docs](https://docs.cosmoconsult.com/de-de/cloud-service/devops-docker-selfservice/) to learn more.

## Actions

| Name | Description |
| :-- | :-- |
| [Create Containers](Actions/CreateContainers) | Create a COSMO Alpaca container for each project |
| [Get Configs For Sync](Actions/GetConfigsForSync) | Find all secret names and encode specified variables to prepare for synchronization |
| [Initialization](Actions/Initialization) | Initialize COSMO Alpaca |
| [Remove Containers](Actions/RemoveContainers) | Remove COSMO Alpaca containers |
| [Sync Configs](Actions/SyncConfigs) | Sync secrets and variables to the COSMO Alpaca backend for development containers |
| [Update System Files](Actions/UpdateSystemFiles) | Update the COSMO Alpaca System Files |
| [Update Alpaca System Files](UpdateAlpacaSystemFiles) **(Deprecated)** | Update COSMO Alpaca system files |

## Branches

| Name | Description |
| :-- | :-- |
| [main](https://github.com/cosmoconsult/Alpaca-Actions/tree/main) | Preview of unreleased changes |
| vX.Y | Releases |