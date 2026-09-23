export const tools = [
  { name: 'Storage', art: 'bars', line: 'Finds the largest files in a folder and totals them by type.' },
  { name: 'Uninstaller', art: 'orbit', line: 'Removes apps and Homebrew or npm packages, along with their caches, preferences and support files.' },
  { name: 'Junk & Leftovers', art: 'tray', line: 'Clears caches, logs, temporary files and files left by deleted apps.' },
  { name: 'Updates', art: 'dial', line: 'Checks Homebrew, npm and App Store apps for updates when you ask.' },
  { name: 'Privacy', art: 'lock', line: 'Opens each Privacy & Security setting and can reset an app’s permissions.' },
  { name: 'Discover & Install', art: 'grid', line: 'Installs apps and developer tools from a catalog of 60 through Homebrew and npm.' },
];

export const steps = [
  ['Discover', 'Finds the app and the files that belong to it.'],
  ['Explain', 'Shows each item’s size and why it matched.'],
  ['Select', 'Selects exact matches. Name-only matches stay unselected.'],
  ['Preview', 'Lists everything that will change.'],
  ['Journal', 'Saves the plan to disk before starting.'],
  ['Revalidate', 'Checks each file again right before moving it.'],
  ['Execute', 'Moves files to the Trash and uninstalls packages with their package manager.'],
  ['Report', 'Records the result for each item.'],
];

export const shots = [
  { title: 'Overview', src: 'images/viper-overview.png', alt: 'Viper Overview: available and used space on Macintosh HD with a 53% used ring, above cards for each tool.' },
  { title: 'Junk & Leftovers', src: 'images/viper-junk.png', alt: 'Viper Junk & Leftovers before a scan.' },
  { title: 'Updates', src: 'images/viper-updates.png', alt: 'Viper Updates before checking for updates.' },
  { title: 'Discover', src: 'images/viper-discover.png', alt: 'Viper Discover & Install catalog listing developer apps with their source and install state.' },
];
