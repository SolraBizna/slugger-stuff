These are the components of a simple, but powerful, rsync-based incremental(ish) backup system. It hardlinks files that don't change between backups, making each separate backup a complete backup but saving disk space that would've been used by duplicate files.

# Server Setup

Install Lua 5.2 and a version of rsync greater than 3. If you want to clone this git repository directly, install git as well.

Create a backup user. In this example, the user will be named `slugger`. Make sure the `slugger` user can read the `slugger-stuff` directory.

Create a symlink to `slugger-snap.sh` in `/usr/local/bin/`:

    ln -s /path/to/slugger-stuff/slugger-snap.sh /usr/local/bin/slugger-snap

(Note the lack of a trailing `.sh` on the second `slugger-snap`, and that both paths are absolute.)

Create a filesystem (or, in a pinch, directory) to store backups in. I use `/meat`, which makes the rest of my backup server like bread and sauce in my "backup sandwich", I guess. A more pragmatic path might be `/backups`. Wherever this directory is, give `slugger` access to this directory. (You should never put anything in there outside of Slugger's control, or it might get confused!)

## Optional: `slugger-trim`

Add entries to `slugger`'s `crontab` that use `slugger-trim` to coalesce backups. `slugger-trim` is a bit unwieldy; it works by treating backup datestamps as numbers, and separating the backups into buckets by chopping a few digits off the right.

Example crontab:

    # in previous minutes, keep hourly snapshots
    0 1-23 * * * /home/slugger/slugger-stuff/slugger-trim.lua /meat 100 10000
    # in previous days, keep daily snapshots
    0 0 2-31 * * /home/slugger/slugger-stuff/slugger-trim.lua /meat 1000000 1000000
    # in previous months, keep monthly snapshots
    0 0 1 * * /home/slugger/slugger-stuff/slugger-trim.lua /meat 100000000 100000000

Let's use the first entry as an example. We have the following backups:

- @2017.08.08-1731.29
- @2017.08.08-1737.18
- @2017.08.08-1820.59
- @2017.08.08-1822.07

And the current time is 6:22PM on August 8, 2017.

The first step is to see which backups need to be *kept*. It divides each backup timestamp by the first number parameter, which it calls the _grace period_. In this case, it's 100. Dividing by 100 is the same as cutting off the rightmost two digits.

This has the following results:

- @2017.08.08-1731<del>.29</del>: Not within grace period
- @2017.08.08-1737<del>.18</del>: Not within grace period
- @2017.08.08-1820<del>.59</del>: Not within grace period
- @2017.08.08-1822<del>.07</del>: Within grace period

The last backup falls within the grace period, because the leftover digits match those of the current time. It will not be touched in any way. The other three make it to the next round.

`slugger-trim` divides the original timestamp (not the post-grace-period-divison one) by the second number parameter, which it calls the _resolution_. It then puts the backups into buckets, depending on the remaining digits. Results:

- (2017.08.08-17 bucket)
    - @2017.08.08-17<del>31.29</del>: Not latest in bucket, delete
    - @2017.08.08-17<del>37.18</del>: Latest in bucket, keep
- (2017.08.08-18 bucket)
    - @2017.08.08-18<del>20.59</del>: Latest in bucket, keep

The first backup will be deleted. The second and third will be kept, with the now-extraneous digits of their timestamps trimmed away. The final result:

- @2017.08.08-17
- @2017.08.08-18
- @2017.08.08-1822.07

If *grace period* and *resolution* are both 0, `slugger-trim` performs a different operation. This mode should be used when disk space is too low to complete a backup. In this mode, `slugger-trim` will delete the oldest backup that exists, as long as there is at least one newer *complete* (i.e. timestamped) backup for that system.

So, if we had:

- `/meat/defiant/@2016`
- `/meat/defiant/@2017`
- `/meat/enterprise/@2015`

`/meat/defiant/@2016` would be deleted. `/meat/enterprise/@2015` would be spared, even though it's older, because it is the last remaining complete backup in `/meat/enterprise`.

# Client Setup

Clients need only a POSIX shell, rsync, and OpenSSH. Any system capable of running these programs will work, including Macs, or Windows machines running Cygwin.

Copy `slugger-client.sh` to the client. Slugger's configuration files can either be in `~/.slugger` or in `/etc/slugger`; I recommend the former when running `slugger-client.sh` as a regular user, and the latter when running as root. If both exist, only `~/.slugger` is used.

Required configuration files, along with examples:

- `host`: The Slugger server, possibly including username.  
  `slugger@my-backup-server.local`
- `dir`: The path the backup will be stored in. This should be a subdirectory of the backup directory you chose above.  
  `/meat/defiant`
- `sources`: The list of *absolute* paths you want to back up. Subdirectories are backed up as well, except that `slugger-client` will not cross filesystem boundaries automatically.  
  `/`  
  `/home`  
  `/var`
- `exclude`: Paths and filenames that *will not* be backed up.  
  `nobackup`
  `.cache`
  `/home/me/secret-files`

Optional:

- `extras`: Extra parameters that will be passed to rsync, between the standard options and the list of files.
- `rsh`: The remote shell to use, if not `ssh`. `rsync` will only work if the shell is fairly `ssh`-/`rsh`-like.

Once the configuration is in place, all you have to do is run `slugger-client.sh`. If you want scheduled backups, see `crontab`.

If you want to send additional options without adding them to `extras` (e.g. you [just finished cleaning up after an aborted in-place encryption of your backup drive](https://github.com/SolraBizna/enthunter) and you want to temporarily enable `-c`), pass them to `slugger-client.sh` as arguments. They will be placed after `extras`, but before the list of files.

(Normally, when you run `slugger-client.sh` from a terminal, it will add `--human-readable --progress` to the options. It will not do so on its own if you pass additional command line options. If you want to specify additional options *and* get progress reports, you can add those options yourself.)
