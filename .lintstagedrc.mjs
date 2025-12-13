import { execSync } from 'child_process';

// Check if a command exists
const commandExists = (cmd) => {
  try {
    execSync(`which ${cmd}`, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
};

// Check if SwiftLint works (requires Xcode, not just CommandLineTools)
const swiftLintWorks = () => {
  try {
    execSync('swiftlint version', { stdio: 'ignore' });
    // Test if SourceKit is available by running a simple lint
    execSync('echo "" | swiftlint lint --use-stdin 2>/dev/null', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
};

const hasSwiftFormat = commandExists('swiftformat');
const hasSwiftLint = commandExists('swiftlint') && swiftLintWorks();

if (commandExists('swiftlint') && !hasSwiftLint) {
  console.log(
    '⚠️  SwiftLint installed but SourceKit unavailable. Run: sudo xcode-select -s /Applications/Xcode.app'
  );
}

export default {
  // TypeScript/JavaScript files in packages and services
  '{packages,services}/**/*.{ts,tsx,js,jsx}': (filenames) => [
    `eslint --fix ${filenames.join(' ')}`,
    `prettier --write ${filenames.join(' ')}`,
  ],

  // JSON/YAML/Markdown formatting (excluding package-lock.json)
  '**/*.{json,yml,yaml,md}': (filenames) => {
    const filtered = filenames.filter((f) => !f.includes('package-lock.json'));
    if (filtered.length === 0) return [];
    return [`prettier --write ${filtered.join(' ')}`];
  },

  // TypeScript type-check (staged files only)
  '{packages,services}/**/*.{ts,tsx}': (filenames) =>
    `npx tsc-files --noEmit ${filenames.join(' ')}`,

  // Swift files - format (and lint if SourceKit available)
  'apps/**/*.swift': (filenames) => {
    const commands = [];
    if (hasSwiftFormat) {
      commands.push(`swiftformat ${filenames.join(' ')}`);
    }
    if (hasSwiftLint) {
      commands.push(`swiftlint lint --fix ${filenames.join(' ')}`);
    }
    if (!hasSwiftFormat && !hasSwiftLint) {
      console.log(
        '⚠️  SwiftLint/SwiftFormat not installed. Run: brew install swiftlint swiftformat'
      );
    }
    return commands;
  },
};
