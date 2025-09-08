# Uninstallomator

![](https://img.shields.io/github/v/release/robjschroeder/Uninstallomator)
![](https://img.shields.io/github/downloads/robjschroeder/Uninstallomator/latest/total)
![](https://img.shields.io/badge/macOS-10.14%2B-success)
![](https://img.shields.io/github/license/robjschroeder/Uninstallomator)

_The one uninstaller script to rule them all._

Uninstallomator is a flexible, scriptable solution for automating the removal of macOS applications and their associated files. Inspired by the Installomator project, Uninstallomator helps MacAdmins and IT professionals streamline the process of uninstalling apps, cleaning up system and user files, and removing related launch agents, daemons, and package receipts.

Uninstallomator is built from modular fragments, making it easy to maintain, extend, and contribute new app labels. The script is designed for reliability and safety, but as with any automation tool, it’s important to test thoroughly in your environment before deploying to production.

**Always test carefully and thoroughly in your environment before going to production!**

Every environment is unique, and while Uninstallomator aims to be robust, edge cases may exist. Please review and test your uninstall workflows to ensure they meet your needs.

## Support and Contributing

If you’d like to contribute new labels or improvements, please edit the files in the `fragments` directory. The main `Uninstallomator.sh` script is assembled from these fragments and will be overwritten during builds. See the [README.md](utils/README.md) in the `utils` directory for detailed instructions.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing.

## Authors and Contributors

Uninstallomator was created by [Robert Schroeder](https://github.com/robjschroeder), with inspiration from the Installomator team and the broader MacAdmins community.

Thank you to everyone who has contributed ideas, labels, and improvements!
