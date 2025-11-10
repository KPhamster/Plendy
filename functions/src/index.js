const admin = require("firebase-admin");

admin.initializeApp();

// Force FieldValue import so bundlers/tree-shakers keep it available
// eslint-disable-next-line no-unused-vars
const { FieldValue } = admin.firestore;

// Export other functions if you have them
// exports.myOtherFunction = require("./myOtherFunction");

// Export the user data deletion function triggered by auth events
exports.deleteUserData = require("./delete_user").deleteUserData;

// Export the user data deletion request function triggered by HTTP
exports.requestUserDataDeletion = require("./request_delete_user").requestUserDataDeletion;

// Export experience share handlers
exports.onExperienceShareCreate = require("./shares").onExperienceShareCreate;
exports.onExperienceShareAcceptCollab = require("./shares").onExperienceShareAcceptCollab;
exports.publicShare = require("./shares").publicShare;

// Export share_permissions triggers for denormalization
exports.onSharePermissionCreate = require("./share_permissions").onSharePermissionCreate;
exports.onSharePermissionUpdate = require("./share_permissions").onSharePermissionUpdate;
exports.onSharePermissionDelete = require("./share_permissions").onSharePermissionDelete;

// Placeholder exports for category/experience denormalization (icon/color) if needed later
// exports.onExperienceWriteDenorm = require("./experience_denorm").onExperienceWriteDenorm;
