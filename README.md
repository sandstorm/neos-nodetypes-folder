# Neos Folder NodeType

[![Latest Stable Version](https://poser.pugx.org/sandstorm/neos-nodetypes-folder/v/stable)](https://packagist.org/packages/sandstorm/neos-nodetypes-folder)

> [!NOTE]
> This was originally a fork of [breadlesscode/neos-nodetypes-folder](https://github.com/breadlesscode/neos-nodetypes-folder).
> The original author and us decided to split maintenance of the package.
> While we maintain the package for all Neos versions >= 9, you can still use the original package for
> neos versions below 9.
> Just make sure to install the respective package (so either `breadlesscode/neos-nodetypes-folder` or `sandstorm/neos-nodetypes-folder`)
> and also use the correct nodetype: `Breadlesscode.NodeTypes.Folder:Document.Folder` or `Sandstorm.NodeTypes.Folder:Document.Folder`.

| Package                                                                                       | Neos Version |
| --------------------------------------------------------------------------------------------- | ------------ |
| [breadlesscode/neos-nodetypes-folder](https://github.com/breadlesscode/neos-nodetypes-folder) | < 9.0        |
| [sandstorm/neos-nodetypes-folder](https://github.com/sandstorm/neos-nodetypes-folder)         | >= 9.0       |

This Neos Plugin contains a folder node type. This folder **isn't rendered in the URI** by default.

The main idea and code is from [@sebobo](https://gist.github.com/Sebobo) from [this Gist](https://gist.github.com/Sebobo/7b12f8e46778321f7b1b02d4b9aaad85). Thanks for that!!!

## Warning

This package overrides the `DocumentUriPathProjection` from the neos core!

## Installation

Most of the time you have to make small adjustments to a package (e.g. the configuration in Settings.yaml). Because of that, it is important to add the corresponding package to the composer manfest of your theme package. Mostly this is the site package located under `Packages/Sites/`. To install it correctly, go to your theme package (e.g. `Packages/Sites/Foo.Bar`) and run the following command:

```bash
composer require sandstorm/neos-nodetypes-folder --no-update
```

The `--no-update` command prevents other dependencies from being updated. After the package was added to your theme composer.json, go back to the root of the Neos installation and run composer update. The package is now installed correctly.
