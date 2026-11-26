# Export to Apple Contacts

Open **Navigation menu → Export to Contacts**. Select people from the whole notebook, including people not on the main list. For each person, select fields, choose to create a contact or select the exact existing contact, then review the destination account and confirm. Skip any person. The final screen reports each person's outcome; closing the sheet does not undo contacts already confirmed.

## Field and account rules

- First and last names are independently selectable; empty names are never used to clear a field. At least one name is required to create a contact.
- An exact Kin birthday maps to the Gregorian year, month, and day. Unknown or estimated ages are not exported. Existing non-Gregorian birthdays are not cleared.
- A photo is off by default and offered only when the existing Kin age gate permits it. The selected photo is shown in the review. The account may impose its own storage constraints.
- Notes, allergies, pets, gender, Kin categories, and all relationships are omitted. No automatic export or sync is started by Kin. Once saved, information is subject to the destination account's own sync behavior.
- Creates use the reviewed Apple Contacts default account; updates use the container of the explicitly selected contact. Search uses only accessible contacts and never selects a match by name. Account and email/phone hints distinguish candidates. Visually indistinguishable candidates are not offered for updating by search.
- Kin asks for Contacts access only on proceeding to review. Limited access is supported within iOS's visible subset. If access or the destination changes, re-review. Applying selected values to an existing contact leaves all unselected fields untouched.
- A protected local link records the local contact and container IDs, not any contact fields. It prevents repeat creation. An interrupted or unverified creation is not retried; check Contacts and select the existing card to resume or repair the link. If the card was deleted outside Kin, create the replacement in Contacts first, then explicitly find and select it in Kin. Deleting a Kin person does not delete exported contacts.

## Design choice

Apple's [native new-contact sheet](https://developer.apple.com/documentation/contactsui/cncontactviewcontroller/init(fornewcontact:)) offers system-controlled review but does not give Kin consistent field-by-field conflict review or batch outcomes. A vCard handoff is portable but cannot reliably confirm the target account, the selected existing card, or what actually saved. Kin uses a native [Contacts store save request](https://developer.apple.com/documentation/contacts/cnsaverequest) behind a Kin-owned explicit review, and only fetches matching cards when the user searches or opens an already linked card. No Contacts notes entitlement is requested: safe read/compare is not available without [restricted entitlement](https://developer.apple.com/documentation/contacts/cncontact/note), so notes are not offered for creation or update.

QA uses synthetic people and simulator Contacts only. Before release, verify denied and limited access, an account change, save restrictions, an interrupted create, and visible focus order and correct image handling on a physical iPhone with synthetic contacts.
