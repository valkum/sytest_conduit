SyTest Conduit Plugin
----------------------------------------------------------------

This plugin for [SyTest](https://github.com/matrix-org/sytest) add a homeserver implementation for [Conduit](https://conduit.rs)

For normal SyTest use, download this repository into a directory under `plugins` of your SyTest installation.
If you use the official SyTest Docker container, you can use the `PLUGINS` environment variable to download this plugin on start.
```bash
docker run --rm -it -e PLUGINS="https://github.com/valkum/sytest_conduit/archive/refs/heads/master.zip"
```