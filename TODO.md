So I'm thinking about improving this config a bit, as something easily redistributable and customizable.

At first we need an installer, where the user can select its base, configuration like:
- which module to autoload
- which theme to use (build up all the supported themes by ghosty for nushell, and vivid, and for what is needed)
- which terminal to configure (currently we want only ghosty) (or install if necessary)
- which nerdfont to use (pick like 15 very popular, in the selection menu show example)
- multiplatform installer, for osx, linux, windows
- dont know which technology for this installer tui.. you can do it in the default shells if possible, but if easier to maintain, then a rust binary with ratatui, think this throug for me

Then the nu-conf
- why we use plugins there, why not with the default plugin manager?
- so clean this up, keep the necessary stuff
- want something for the modules to be able to enable them by default or just on use
- select theme persistently
- remove fetch themes from nu_scripts.. you can use for the default building asked for the installer.. 

modules
- templating
- I want something that on the first use, or setting it to default checks the depedencies, and not loads them, just tell what to install, or how to configure properly
- and yeah they should self containt their default config, and provide the user that base records for example that can be overconfigured
- They need all of them an unified README strategy that explains how to use them, how to configure them, whats the purpose and so on.. human readable logical sturctured

completions
- also they should hold their default config, they should be all available by default.. the shipped should be git tracked, but not what the user fetches


distribution, personalization
- config is personal, shipped defaults, user can se, and override them in their gitignored config directory
- so imagine something like, the user pulls this, installs, then the repo updates, they update it, their config lives not in that.. they may have their own.. (like LazyVim distro, but with a shipped base)


Misc
- clean up root env.nu, not needed, check what is unnecessary, we want to keep things minimal
- config files should be nuon or nu, but not json or something else prefer nuon for files, logs etc, formatted

If its too much to process together, just start with building milestones and tickets for github, then you can implement them step by step