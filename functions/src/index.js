const admin = require("firebase-admin");

admin.initializeApp();

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
