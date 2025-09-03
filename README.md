# BlockyPuck
## Dogecoin Core Blockchain Storage Device


![Import Blockchain Screenshot](/images/BlockyPuck.jpg)

BlockyPuck helps you keep a copy of the Dogecoin blockchain ready to go at all times. Do it in style with the included 3D printable case!
The included sync script will help you keep the files up to date on your chosen device, set it up on a Dogebox or whatever device you have the blockchain synced on.

## Contents
- `/CAD` - 3D printable case files
- `/images` - Repo image files
- `/scripts` - Utility scripts

## Hardware
- **Compatible SSD**: DATO ARES Torch Portable External Solid State Drive - [Amazon Link](https://www.amazon.com.au/dp/B0CJRBH9LR?ref_=ppx_hzsearch_conn_dt_b_fed_asin_title_1&th=1)
- **Case**: 3D-printable CAD files included. There's a spot for an AirTag if you'd like to add one in.
- **Assembly hardware**:
  -  3x M3x4mm brass inserts
  - 3x M3x8mm bolts
- **Assembly process**:
  - Print BlockyPuck base and lid
  - Set brass inserts into lid
  - Carefully open up the SSD enclosure using a butterknife or other blunt metal tool
  - Rremove the internal board
  - Place it into the 3D printed BlockyPuck case and assemble

## Keeping BlockyPuck Up-To-Date
On your Dogebox (or any device with a synced Dogecoin blockchain), setup `/scripts/sync_blockchain.sh` to be run reguarly with crontab. This will keep connected storage devices loaded with the latest blockchain data!
See the README file in `/scripts` for more details.

![Import Blockchain Screenshot](/images/BlockyPucks.jpg)

## Use with Dogebox
To quickly get Dogecoin Core up to date on your Dogebox, you can use your BlockyPuck! Ensure the blockchain folders are at the top level of the device - It should look as follows:
```
/blocks/
/chainstate/
```
After installing the Dogecoin Core Pup and connecting your BlockyPuck, goto Settings > Import Blockchain and follow the prompts
![Import Blockchain Screenshot](/images/import-blockchain.png)