# BlockyPuck
## Dogecoin Core Blockchain Storage Device


![Import Blockchain Screenshot](/images/BlockyPuck.jpg)

## Contents
- `/cad` - 3D printable case files
- `/scripts` - Utility scripts

## Hardware
- **Compatible SSD**: DATO ARES Torch Portable External Solid State Drive - [Amazon Link](https://www.amazon.com.au/dp/B0CJRBH9LR?ref_=ppx_hzsearch_conn_dt_b_fed_asin_title_1&th=1)
- **Case**: 3D-printable CAD files included. Supports AirTag.
- **Assembly hardware**:
  -  3x M3x4mm brass inserts
    - 3x M3x8mm bolts

## Dogebox
To get Dogecoin Core up to date on your Dogebox, copy blockchain files from an existing Core installation to the top level of your BlockyPuck (you can use any device with enough storage).
It should look as follows:
```
/blocks/
/chainstate/
```
After installing the Dogecoin Core Pup and connecting your BlockyPuck, goto Settings > Import Blockchain and follow the prompts
![Import Blockchain Screenshot](/images/import-blockchain.png)

## Keeping BlockyPuck Up-To-Date
On a Dogebox or any device with a synced Dogecoin Core, setup `/scripts/sync_blockchain.sh` to keep connected storage devices loaded with the latest blockchain data!

![Import Blockchain Screenshot](/images/BlockyPucks.jpg)