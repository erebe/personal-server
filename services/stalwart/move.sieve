require ["fileinto", "variables", "envelope", "regex", "mailbox"];

# Extract the local-part (before @) from the recipient address
if envelope :regex "to" "^([^@]+)@.*$" {

  if string :is "${1}" "erebe" {
    fileinto "INBOX/_erebe";
  } else {
    set :lower "folder" "INBOX/${1}";
    fileinto :create "${folder}";
  }
  keep;

  stop;
}
