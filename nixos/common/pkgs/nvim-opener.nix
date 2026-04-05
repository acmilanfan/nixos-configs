{ stdenv, lib, apple-sdk_14, ... }:

let
  name = "NvimOpener";
  bundleId = "com.gentooway.nvim-opener";
in
stdenv.mkDerivation {
  pname = name;
  version = "1.1.7";

  dontUnpack = true;

  buildInputs = [
    apple-sdk_14
  ];

  buildPhase = ''
    cat <<EOF > main.m
    #import <Cocoa/Cocoa.h>
    #include <unistd.h>
    #include <stdlib.h>

    @interface AppDelegate : NSObject <NSApplicationDelegate>
    @property (nonatomic, assign) BOOL handledFiles;
    @end

    @implementation AppDelegate

    - (NSString *)findAlacritty {
        NSString *home = NSHomeDirectory();
        NSString *user = NSUserName();
        NSArray *paths = @[
            [home stringByAppendingString:@"/Applications/Home Manager Apps/Alacritty.app/Contents/MacOS/alacritty"],
            [home stringByAppendingString:@"/Applications/Alacritty.app/Contents/MacOS/alacritty"],
            @"/Applications/Alacritty.app/Contents/MacOS/alacritty",
            @"/Applications/Nix Apps/Alacritty.app/Contents/MacOS/alacritty"
        ];

        for (NSString *path in paths) {
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
                return path;
            }
        }
        return nil;
    }

    - (void)launchNvimWithFile:(NSString *)filename {
        NSString *alacritty = [self findAlacritty];
        NSString *userName = NSUserName();
        NSString *home = NSHomeDirectory();

        pid_t pid = fork();
        if (pid == 0) {
            setenv("USER", [userName UTF8String], 1);
            setenv("HOME", [home UTF8String], 1);
            setenv("SHELL", "/bin/zsh", 1);
            setenv("PATH", [[NSString stringWithFormat:@"%@/.nix-profile/bin:/etc/profiles/per-user/%@/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", home, userName] UTF8String], 1);

            NSString *shellCmd;
            if (filename) {
                NSString *dir = [filename stringByDeletingLastPathComponent];
                NSString *safeFile = [filename stringByReplacingOccurrencesOfString:@"'" withString:@"'\\'''"];
                NSString *safeDir = [dir stringByReplacingOccurrencesOfString:@"'" withString:@"'\\'''"];
                shellCmd = [NSString stringWithFormat:@"cd '%@' && nvim '%@'", safeDir, safeFile];
            } else {
                shellCmd = @"nvim";
            }

            if (alacritty) {
                char *args[] = {
                    (char *)[alacritty UTF8String],
                    (char *)"-e",
                    (char *)"zsh",
                    (char *)"-lc",
                    (char *)[shellCmd UTF8String],
                    NULL
                };
                execv(args[0], args);
            } else {
                char *args[] = {
                    (char *)"/usr/bin/open",
                    (char *)"-n",
                    (char *)"-a",
                    (char *)"Alacritty",
                    (char *)"--args",
                    (char *)"-e",
                    (char *)"zsh",
                    (char *)"-lc",
                    (char *)[shellCmd UTF8String],
                    NULL
                };
                execv(args[0], args);
            }
            _exit(1);
        }
    }

    - (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
        self.handledFiles = YES;
        for (NSString *filename in filenames) {
            [self launchNvimWithFile:filename];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }

    - (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.handledFiles) {
                [self launchNvimWithFile:nil];
                [NSApp terminate:nil];
            }
        });
    }
    @end

    int main(int argc, char *argv[]) {
        @autoreleasepool {
            NSApplication *app = [NSApplication sharedApplication];
            AppDelegate *delegate = [[AppDelegate alloc] init];
            [app setDelegate:delegate];
            [app run];
        }
        return 0;
    }
    EOF

    clang -fobjc-arc -framework Cocoa main.m -o ${name}
  '';

  installPhase = ''
    mkdir -p $out/Applications/${name}.app/Contents/MacOS
    mkdir -p $out/Applications/${name}.app/Contents/Resources

    cp ${name} $out/Applications/${name}.app/Contents/MacOS/${name}

    cat <<EOF > $out/Applications/${name}.app/Contents/Info.plist
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleExecutable</key>
        <string>${name}</string>
        <key>CFBundleIdentifier</key>
        <string>${bundleId}</string>
        <key>CFBundleName</key>
        <string>${name}</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>1.1.7</string>
        <key>CFBundleVersion</key>
        <string>12</string>
        <key>LSMinimumSystemVersion</key>
        <string>10.10</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>LSUIElement</key>
        <true/>
        <key>CFBundleDocumentTypes</key>
        <array>
            <dict>
                <key>CFBundleTypeExtensions</key>
                <array>
                    <string>org</string>
                    <string>txt</string>
                    <string>md</string>
                    <string>nix</string>
                    <string>lua</string>
                    <string>sh</string>
                </array>
                <key>CFBundleTypeName</key>
                <string>Document</string>
                <key>CFBundleTypeRole</key>
                <string>Editor</string>
                <key>LSHandlerRank</key>
                <string>Owner</string>
            </dict>
            <dict>
                <key>CFBundleTypeName</key>
                <string>Any File</string>
                <key>CFBundleTypeRole</key>
                <string>Viewer</string>
                <key>LSHandlerRank</key>
                <string>None</string>
                <key>LSItemContentTypes</key>
                <array>
                    <string>public.item</string>
                    <string>public.data</string>
                    <string>public.content</string>
                </array>
            </dict>
        </array>
        <key>UTExportedTypeDeclarations</key>
        <array>
            <dict>
                <key>UTTypeIdentifier</key>
                <string>org.norg.orgmode</string>
                <key>UTTypeDescription</key>
                <string>Org-mode Document</string>
                <key>UTTypeConformsTo</key>
                <array>
                    <string>public.text</string>
                    <string>public.plain-text</string>
                </array>
                <key>UTTypeTagSpecification</key>
                <dict>
                    <key>public.filename-extension</key>
                    <array>
                        <string>org</string>
                    </array>
                </dict>
            </dict>
        </array>
    </dict>
    </plist>
    EOF
  '';

  meta = with lib; {
    description = "A macOS application wrapper to open files in Alacritty with Neovim";
    platforms = platforms.darwin;
  };
}
