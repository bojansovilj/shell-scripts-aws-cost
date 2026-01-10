# Bash Syntax Guide

## Variables

### Declaration and Assignment
```bash
# Variable assignment (no spaces around =)
name="John"
age=25
path="/home/user"

# Using variables
echo $name
echo ${name}    # preferred for clarity
echo "Hello $name"
echo 'Hello $name'  # single quotes prevent expansion
```

### Special Variables
```bash
$0    # Script name
$1    # First argument
$2    # Second argument
$#    # Number of arguments
$@    # All arguments as separate words
$*    # All arguments as single string
$$    # Process ID
$?    # Exit status of last command
```

## Conditionals

### Test Operators
```bash
# String tests
[ -z "$var" ]     # True if string is empty
[ -n "$var" ]     # True if string is not empty
[ "$a" = "$b" ]   # String equality
[ "$a" != "$b" ]  # String inequality

# Numeric tests
[ $a -eq $b ]     # Equal
[ $a -ne $b ]     # Not equal
[ $a -lt $b ]     # Less than
[ $a -le $b ]     # Less than or equal
[ $a -gt $b ]     # Greater than
[ $a -ge $b ]     # Greater than or equal

# File tests
[ -f "$file" ]    # File exists and is regular file
[ -d "$dir" ]     # Directory exists
[ -e "$path" ]    # Path exists
[ -r "$file" ]    # File is readable
[ -w "$file" ]    # File is writable
[ -x "$file" ]    # File is executable
```

### If Statements
```bash
# Basic if
if [ condition ]; then
    commands
fi

# If-else
if [ condition ]; then
    commands
else
    other_commands
fi

# If-elif-else
if [ condition1 ]; then
    commands1
elif [ condition2 ]; then
    commands2
else
    commands3
fi

# Enhanced test [[ ]]
if [[ $var == "pattern"* ]]; then
    echo "Starts with pattern"
fi
```

## Loops

### For Loops
```bash
# Loop over list
for item in apple banana cherry; do
    echo $item
done

# Loop over files
for file in *.txt; do
    echo "Processing $file"
done

# C-style for loop
for ((i=1; i<=10; i++)); do
    echo $i
done

# Loop over command output
for user in $(cat /etc/passwd | cut -d: -f1); do
    echo "User: $user"
done
```

### While Loops
```bash
# Basic while
counter=1
while [ $counter -le 5 ]; do
    echo $counter
    ((counter++))
done

# Read file line by line
while IFS= read -r line; do
    echo "Line: $line"
done < file.txt
```

## Case Statements
```bash
case $variable in
    pattern1)
        commands1
        ;;
    pattern2|pattern3)
        commands2
        ;;
    *)
        default_commands
        ;;
esac

# Example
case $1 in
    --help|-h)
        show_help
        ;;
    --version|-v)
        show_version
        ;;
    *)
        echo "Unknown option: $1"
        ;;
esac
```

## Functions
```bash
# Function definition
function_name() {
    local var="local variable"
    echo "Hello $1"
    return 0
}

# Call function
function_name "World"

# Function with local variables
calculate() {
    local num1=$1
    local num2=$2
    local result=$((num1 + num2))
    echo $result
}

result=$(calculate 5 3)
```

## Command Substitution
```bash
# Modern syntax (preferred)
current_date=$(date)
file_count=$(ls | wc -l)

# Old syntax
current_date=`date`
file_count=`ls | wc -l`
```

## Parameter Expansion
```bash
# Basic expansion
echo ${var}

# Default values
echo ${var:-default}        # Use default if var is unset/empty
echo ${var:=default}        # Set var to default if unset/empty
echo ${var:+alternative}    # Use alternative if var is set

# String manipulation
${var#pattern}     # Remove shortest match from beginning
${var##pattern}    # Remove longest match from beginning
${var%pattern}     # Remove shortest match from end
${var%%pattern}    # Remove longest match from end
${var/old/new}     # Replace first occurrence
${var//old/new}    # Replace all occurrences

# Length and substrings
${#var}            # Length of string
${var:start:length} # Substring
```

## Arrays
```bash
# Array declaration
arr=("apple" "banana" "cherry")
declare -a arr=("apple" "banana" "cherry")

# Access elements
echo ${arr[0]}     # First element
echo ${arr[@]}     # All elements
echo ${#arr[@]}    # Array length

# Loop through array
for item in "${arr[@]}"; do
    echo $item
done
```

## Input/Output Redirection
```bash
# Output redirection
command > file          # Redirect stdout to file (overwrite)
command >> file         # Redirect stdout to file (append)
command 2> file         # Redirect stderr to file
command &> file         # Redirect both stdout and stderr
command 2>/dev/null     # Discard stderr

# Input redirection
command < file          # Read input from file
command <<< "string"    # Here string

# Pipes
command1 | command2     # Pipe stdout of command1 to stdin of command2
```

## Arithmetic
```bash
# Arithmetic expansion
result=$((5 + 3))
result=$((var1 * var2))

# Increment/decrement
((counter++))
((counter--))
((counter += 5))

# Let command
let "result = 5 + 3"
let "counter++"
```

## String Operations
```bash
# Concatenation
full_name="$first_name $last_name"
path="$dir/$file"

# String comparison
if [[ "$str1" == "$str2" ]]; then
    echo "Equal"
fi

# Pattern matching
if [[ "$filename" == *.txt ]]; then
    echo "Text file"
fi
```

## Error Handling
```bash
# Exit on error
set -e

# Check command success
if command; then
    echo "Success"
else
    echo "Failed"
fi

# Short-circuit operators
command && echo "Success" || echo "Failed"

# Check exit status
command
if [ $? -eq 0 ]; then
    echo "Command succeeded"
fi
```

## Common Patterns

### Argument Parsing
```bash
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -f|--file)
            FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done
```

### File Processing
```bash
# Check if file exists
if [ ! -f "$filename" ]; then
    echo "File not found: $filename"
    exit 1
fi

# Process each line
while IFS= read -r line; do
    # Process $line
    echo "Processing: $line"
done < "$filename"
```

### Error Messages
```bash
# Print to stderr
echo "Error: Something went wrong" >&2

# Exit with error
die() {
    echo "Error: $1" >&2
    exit 1
}

# Usage
[ -f "$file" ] || die "File not found: $file"
```

## Best Practices

1. **Quote variables**: Use `"$var"` instead of `$var`
2. **Use [[ ]] for tests**: More powerful than [ ]
3. **Use local variables in functions**
4. **Check command success**: Use `set -e` or check `$?`
5. **Use meaningful variable names**
6. **Add comments for complex logic**
7. **Use shellcheck for syntax validation**

## Debugging
```bash
# Debug mode
set -x          # Print commands before execution
set +x          # Turn off debug mode

# Verbose mode
set -v          # Print shell input lines

# Strict mode
set -euo pipefail   # Exit on error, undefined vars, pipe failures
```