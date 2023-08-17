# boblbee

## What is this?

`boblbee` is a collection of dotfiles, scripts, and widgets that I use to set up my Mac, to my own taste and specification. There are many dotfiles, but these are mine.

The name `boblbee` comes from [Point 65](https://boblbee.point65.com/pages/about-us-point-65-sweden) - a Swedish company founded in the late 90s to produce hard-case backpacks with spine protection, lumbar support, and loud colourways. I've used and loved them since the early 2000s, and carried my life in them, so it made sense to carry my digital detritus in one, too.

Feel free to fork, submit PRs, and open issues.

## What it's not

`boblbee` is not a one-stop shop for everyone and their dog; it's not intended to be something you run once, having not read the contentns and understood the changes.

Don't use this if you're not at ease reading basic shell scripts, interpreting Apple's `defaults write` commands, or if you're unwilling to blast your machine config away and start over if something breaks.

## Using `boblbee`

I like to keep my repos in a local workspace. Given that this is the very first thing I'll install, I'll create the path at the time I clone the repo.

    mkdir -p workspace/gl52/boblbee && git clone https://github.com/matdotcx/boblbee.git ~/workspace/gl52/boblbee

Once the clone has completed, you can then initialise boblebee with the following command

    cd ~/workspace/gl52/boblbee/scripts $$ ./index.sh

Follow the instructions, and remember, never run code you've not read and understood.
