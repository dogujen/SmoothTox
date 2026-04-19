#include "tox_wrapper.h"

#include <stdlib.h>
#include <string.h>
#include <tox/tox.h>

struct ToxWrapper {
    Tox *tox;

    void *swift_user_data;
    toxw_self_connection_status_cb self_connection_status_callback;
    toxw_friend_connection_status_cb friend_connection_status_callback;
    toxw_friend_name_cb friend_name_callback;
    toxw_friend_message_cb friend_message_callback;
    toxw_friend_request_cb friend_request_callback;
    toxw_file_recv_cb file_recv_callback;
    toxw_file_recv_chunk_cb file_recv_chunk_callback;
    toxw_file_chunk_request_cb file_chunk_request_callback;
    toxw_file_recv_control_cb file_recv_control_callback;
};

static void toxw_on_self_connection_status(Tox *tox, Tox_Connection connection_status, void *user_data) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->self_connection_status_callback == NULL) {
        return;
    }

    wrapper->self_connection_status_callback(wrapper->swift_user_data, (uint32_t)connection_status);
}

static void toxw_on_friend_connection_status(Tox *tox, uint32_t friend_number, Tox_Connection connection_status, void *user_data) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->friend_connection_status_callback == NULL) {
        return;
    }

    wrapper->friend_connection_status_callback(wrapper->swift_user_data, friend_number, (uint32_t)connection_status);
}

static void toxw_on_friend_name(Tox *tox, uint32_t friend_number, const uint8_t *name, size_t length, void *user_data) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->friend_name_callback == NULL) {
        return;
    }

    wrapper->friend_name_callback(wrapper->swift_user_data, friend_number, name, length);
}

static void toxw_on_friend_message(
    Tox *tox,
    uint32_t friend_number,
    Tox_Message_Type message_type,
    const uint8_t *message,
    size_t length,
    void *user_data
) {
    (void)tox;
    (void)message_type;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->friend_message_callback == NULL) {
        return;
    }

    wrapper->friend_message_callback(wrapper->swift_user_data, friend_number, message, length);
}

static void toxw_on_friend_request(
    Tox *tox,
    const uint8_t *public_key,
    const uint8_t *message,
    size_t length,
    void *user_data
) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->friend_request_callback == NULL) {
        return;
    }

    wrapper->friend_request_callback(wrapper->swift_user_data, public_key, message, length);
}

static void toxw_on_file_recv(
    Tox *tox,
    uint32_t friend_number,
    uint32_t file_number,
    uint32_t kind,
    uint64_t file_size,
    const uint8_t *filename,
    size_t filename_length,
    void *user_data
) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->file_recv_callback == NULL) {
        return;
    }

    wrapper->file_recv_callback(wrapper->swift_user_data, friend_number, file_number, kind, file_size, filename, filename_length);
}

static void toxw_on_file_recv_chunk(
    Tox *tox,
    uint32_t friend_number,
    uint32_t file_number,
    uint64_t position,
    const uint8_t *data,
    size_t length,
    void *user_data
) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->file_recv_chunk_callback == NULL) {
        return;
    }

    wrapper->file_recv_chunk_callback(wrapper->swift_user_data, friend_number, file_number, position, data, length);
}

static void toxw_on_file_chunk_request(
    Tox *tox,
    uint32_t friend_number,
    uint32_t file_number,
    uint64_t position,
    size_t length,
    void *user_data
) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->file_chunk_request_callback == NULL) {
        return;
    }

    wrapper->file_chunk_request_callback(wrapper->swift_user_data, friend_number, file_number, position, length);
}

static void toxw_on_file_recv_control(
    Tox *tox,
    uint32_t friend_number,
    uint32_t file_number,
    Tox_File_Control control,
    void *user_data
) {
    (void)tox;

    ToxWrapper *wrapper = (ToxWrapper *)user_data;
    if (wrapper == NULL || wrapper->file_recv_control_callback == NULL) {
        return;
    }

    wrapper->file_recv_control_callback(wrapper->swift_user_data, friend_number, file_number, (uint32_t)control);
}

static ToxWrapper *toxw_create_internal(
    const uint8_t *savedata,
    size_t savedata_length,
    uint32_t proxy_type,
    const char *proxy_host,
    uint16_t proxy_port,
    int32_t *out_error_code
) {
    Tox_Err_Options_New options_error = TOX_ERR_OPTIONS_NEW_OK;
    Tox_Options *options = tox_options_new(&options_error);

    if (options == NULL || options_error != TOX_ERR_OPTIONS_NEW_OK) {
        if (out_error_code != NULL) {
            *out_error_code = (int32_t)options_error;
        }
        return NULL;
    }

    if (savedata != NULL && savedata_length > 0) {
        tox_options_set_savedata_type(options, TOX_SAVEDATA_TYPE_TOX_SAVE);
        tox_options_set_savedata_data(options, savedata, savedata_length);
    }

    if (proxy_type > 0 && proxy_host != NULL && proxy_host[0] != '\0' && proxy_port > 0) {
        tox_options_set_proxy_type(options, (Tox_Proxy_Type)proxy_type);
        tox_options_set_proxy_host(options, proxy_host);
        tox_options_set_proxy_port(options, proxy_port);
    }

    Tox_Err_New new_error = TOX_ERR_NEW_OK;
    Tox *tox = tox_new(options, &new_error);
    tox_options_free(options);

    if (tox == NULL || new_error != TOX_ERR_NEW_OK) {
        if (out_error_code != NULL) {
            *out_error_code = (int32_t)new_error;
        }
        return NULL;
    }

    ToxWrapper *wrapper = (ToxWrapper *)calloc(1, sizeof(ToxWrapper));
    if (wrapper == NULL) {
        tox_kill(tox);
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return NULL;
    }

    wrapper->tox = tox;

    tox_callback_self_connection_status(tox, toxw_on_self_connection_status);
    tox_callback_friend_connection_status(tox, toxw_on_friend_connection_status);
    tox_callback_friend_name(tox, toxw_on_friend_name);
    tox_callback_friend_message(tox, toxw_on_friend_message);
    tox_callback_friend_request(tox, toxw_on_friend_request);
    tox_callback_file_recv(tox, toxw_on_file_recv);
    tox_callback_file_recv_chunk(tox, toxw_on_file_recv_chunk);
    tox_callback_file_chunk_request(tox, toxw_on_file_chunk_request);
    tox_callback_file_recv_control(tox, toxw_on_file_recv_control);

    if (out_error_code != NULL) {
        *out_error_code = 0;
    }

    return wrapper;
}

ToxWrapper *toxw_create(int32_t *out_error_code) {
    return toxw_create_internal(NULL, 0, 0, NULL, 0, out_error_code);
}

ToxWrapper *toxw_create_from_savedata(const uint8_t *savedata, size_t savedata_length, int32_t *out_error_code) {
    return toxw_create_internal(savedata, savedata_length, 0, NULL, 0, out_error_code);
}

ToxWrapper *toxw_create_with_proxy(
    const uint8_t *savedata,
    size_t savedata_length,
    uint32_t proxy_type,
    const char *proxy_host,
    uint16_t proxy_port,
    int32_t *out_error_code
) {
    return toxw_create_internal(savedata, savedata_length, proxy_type, proxy_host, proxy_port, out_error_code);
}

void toxw_destroy(ToxWrapper *wrapper) {
    if (wrapper == NULL) {
        return;
    }

    if (wrapper->tox != NULL) {
        tox_kill(wrapper->tox);
    }

    free(wrapper);
}

void toxw_set_callbacks(
    ToxWrapper *wrapper,
    void *swift_user_data,
    toxw_self_connection_status_cb self_connection_status_callback,
    toxw_friend_connection_status_cb friend_connection_status_callback,
    toxw_friend_name_cb friend_name_callback,
    toxw_friend_message_cb friend_message_callback,
    toxw_friend_request_cb friend_request_callback,
    toxw_file_recv_cb file_recv_callback,
    toxw_file_recv_chunk_cb file_recv_chunk_callback,
    toxw_file_chunk_request_cb file_chunk_request_callback,
    toxw_file_recv_control_cb file_recv_control_callback
) {
    if (wrapper == NULL) {
        return;
    }

    wrapper->swift_user_data = swift_user_data;
    wrapper->self_connection_status_callback = self_connection_status_callback;
    wrapper->friend_connection_status_callback = friend_connection_status_callback;
    wrapper->friend_name_callback = friend_name_callback;
    wrapper->friend_message_callback = friend_message_callback;
    wrapper->friend_request_callback = friend_request_callback;
    wrapper->file_recv_callback = file_recv_callback;
    wrapper->file_recv_chunk_callback = file_recv_chunk_callback;
    wrapper->file_chunk_request_callback = file_chunk_request_callback;
    wrapper->file_recv_control_callback = file_recv_control_callback;
}

void toxw_iterate(ToxWrapper *wrapper) {
    if (wrapper == NULL || wrapper->tox == NULL) {
        return;
    }

    tox_iterate(wrapper->tox, wrapper);
}

uint32_t toxw_iteration_interval_ms(const ToxWrapper *wrapper) {
    if (wrapper == NULL || wrapper->tox == NULL) {
        return 16;
    }

    return tox_iteration_interval(wrapper->tox);
}

bool toxw_bootstrap(ToxWrapper *wrapper, const char *host, uint16_t port, const uint8_t *public_key_32, int32_t *out_error_code) {
    if (wrapper == NULL || wrapper->tox == NULL || host == NULL || public_key_32 == NULL) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_Bootstrap bootstrap_error = TOX_ERR_BOOTSTRAP_OK;
    const bool ok = tox_bootstrap(wrapper->tox, host, port, public_key_32, &bootstrap_error);

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)bootstrap_error;
    }

    return ok && bootstrap_error == TOX_ERR_BOOTSTRAP_OK;
}

bool toxw_get_self_address(const ToxWrapper *wrapper, uint8_t *out_address_38) {
    if (wrapper == NULL || wrapper->tox == NULL || out_address_38 == NULL) {
        return false;
    }

    tox_self_get_address(wrapper->tox, out_address_38);
    return true;
}

bool toxw_set_self_name(ToxWrapper *wrapper, const uint8_t *name, size_t length, int32_t *out_error_code) {
    if (wrapper == NULL || wrapper->tox == NULL || name == NULL || length == 0) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_Set_Info error = TOX_ERR_SET_INFO_OK;
    const bool ok = tox_self_set_name(wrapper->tox, name, length, &error);

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)error;
    }

    return ok && error == TOX_ERR_SET_INFO_OK;
}

bool toxw_get_self_name(const ToxWrapper *wrapper, uint8_t *out_name, size_t *inout_length) {
    if (wrapper == NULL || wrapper->tox == NULL || out_name == NULL || inout_length == NULL) {
        return false;
    }

    const size_t required = tox_self_get_name_size(wrapper->tox);
    if (required == 0 || *inout_length < required) {
        *inout_length = required;
        return false;
    }

    tox_self_get_name(wrapper->tox, out_name);
    *inout_length = required;
    return true;
}

size_t toxw_get_savedata_size(const ToxWrapper *wrapper) {
    if (wrapper == NULL || wrapper->tox == NULL) {
        return 0;
    }

    return tox_get_savedata_size(wrapper->tox);
}

bool toxw_get_savedata(const ToxWrapper *wrapper, uint8_t *out_savedata, size_t capacity, size_t *out_written) {
    if (wrapper == NULL || wrapper->tox == NULL || out_savedata == NULL) {
        return false;
    }

    const size_t size = tox_get_savedata_size(wrapper->tox);
    if (size == 0 || capacity < size) {
        if (out_written != NULL) {
            *out_written = size;
        }
        return false;
    }

    tox_get_savedata(wrapper->tox, out_savedata);

    if (out_written != NULL) {
        *out_written = size;
    }

    return true;
}

uint32_t toxw_get_friend_count(const ToxWrapper *wrapper) {
    if (wrapper == NULL || wrapper->tox == NULL) {
        return 0;
    }

    const size_t size = tox_self_get_friend_list_size(wrapper->tox);
    return (uint32_t)size;
}

uint32_t toxw_get_friend_list(const ToxWrapper *wrapper, uint32_t *out_friend_numbers, uint32_t capacity) {
    if (wrapper == NULL || wrapper->tox == NULL || out_friend_numbers == NULL || capacity == 0) {
        return 0;
    }

    const size_t full_size = tox_self_get_friend_list_size(wrapper->tox);
    if (full_size == 0) {
        return 0;
    }

    uint32_t *scratch = (uint32_t *)calloc(full_size, sizeof(uint32_t));
    if (scratch == NULL) {
        return 0;
    }

    tox_self_get_friend_list(wrapper->tox, scratch);
    const size_t copy_count = full_size < (size_t)capacity ? full_size : (size_t)capacity;
    memcpy(out_friend_numbers, scratch, copy_count * sizeof(uint32_t));
    free(scratch);

    return (uint32_t)copy_count;
}

bool toxw_get_friend_name(const ToxWrapper *wrapper, uint32_t friend_number, uint8_t *out_name, size_t *inout_length) {
    if (wrapper == NULL || wrapper->tox == NULL || out_name == NULL || inout_length == NULL) {
        return false;
    }

    Tox_Err_Friend_Query query_error = TOX_ERR_FRIEND_QUERY_OK;
    const size_t required_size = tox_friend_get_name_size(wrapper->tox, friend_number, &query_error);

    if (query_error != TOX_ERR_FRIEND_QUERY_OK || required_size == 0 || *inout_length < required_size) {
        *inout_length = required_size;
        return false;
    }

    tox_friend_get_name(wrapper->tox, friend_number, out_name, &query_error);
    if (query_error != TOX_ERR_FRIEND_QUERY_OK) {
        return false;
    }

    *inout_length = required_size;
    return true;
}

bool toxw_get_friend_public_key(const ToxWrapper *wrapper, uint32_t friend_number, uint8_t *out_public_key_32) {
    if (wrapper == NULL || wrapper->tox == NULL || out_public_key_32 == NULL) {
        return false;
    }

    Tox_Err_Friend_Get_Public_Key error = TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK;
    tox_friend_get_public_key(wrapper->tox, friend_number, out_public_key_32, &error);
    return error == TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK;
}

bool toxw_send_message(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    const uint8_t *message,
    size_t message_length,
    uint32_t *out_message_id,
    int32_t *out_error_code
) {
    if (wrapper == NULL || wrapper->tox == NULL || message == NULL || message_length == 0) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_Friend_Send_Message send_error = TOX_ERR_FRIEND_SEND_MESSAGE_OK;
    const uint32_t message_id = tox_friend_send_message(
        wrapper->tox,
        friend_number,
        TOX_MESSAGE_TYPE_NORMAL,
        message,
        message_length,
        &send_error
    );

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)send_error;
    }

    if (send_error != TOX_ERR_FRIEND_SEND_MESSAGE_OK) {
        return false;
    }

    if (out_message_id != NULL) {
        *out_message_id = message_id;
    }

    return true;
}

bool toxw_add_friend_norequest(
    ToxWrapper *wrapper,
    const uint8_t *public_key_32,
    uint32_t *out_friend_number,
    int32_t *out_error_code
) {
    if (wrapper == NULL || wrapper->tox == NULL || public_key_32 == NULL) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_Friend_Add add_error = TOX_ERR_FRIEND_ADD_OK;
    const uint32_t friend_number = tox_friend_add_norequest(wrapper->tox, public_key_32, &add_error);

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)add_error;
    }

    if (add_error != TOX_ERR_FRIEND_ADD_OK) {
        return false;
    }

    if (out_friend_number != NULL) {
        *out_friend_number = friend_number;
    }

    return true;
}

bool toxw_add_friend(
    ToxWrapper *wrapper,
    const uint8_t *address_38,
    const uint8_t *message,
    size_t message_length,
    uint32_t *out_friend_number,
    int32_t *out_error_code
) {
    if (wrapper == NULL || wrapper->tox == NULL || address_38 == NULL || message == NULL || message_length == 0) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_Friend_Add add_error = TOX_ERR_FRIEND_ADD_OK;
    const uint32_t friend_number = tox_friend_add(wrapper->tox, address_38, message, message_length, &add_error);

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)add_error;
    }

    if (add_error != TOX_ERR_FRIEND_ADD_OK) {
        return false;
    }

    if (out_friend_number != NULL) {
        *out_friend_number = friend_number;
    }

    return true;
}

bool toxw_file_send(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t kind,
    uint64_t file_size,
    const uint8_t *file_id_32,
    const uint8_t *filename,
    size_t filename_length,
    uint32_t *out_file_number,
    int32_t *out_error_code
) {
    if (wrapper == NULL || wrapper->tox == NULL || filename == NULL || filename_length == 0) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_File_Send error = TOX_ERR_FILE_SEND_OK;
    const uint32_t file_number = tox_file_send(
        wrapper->tox,
        friend_number,
        kind,
        file_size,
        file_id_32,
        filename,
        filename_length,
        &error
    );

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)error;
    }

    if (error != TOX_ERR_FILE_SEND_OK) {
        return false;
    }

    if (out_file_number != NULL) {
        *out_file_number = file_number;
    }

    return true;
}

bool toxw_file_control(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t file_number,
    uint32_t control,
    int32_t *out_error_code
) {
    if (wrapper == NULL || wrapper->tox == NULL) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_File_Control error = TOX_ERR_FILE_CONTROL_OK;
    const bool ok = tox_file_control(wrapper->tox, friend_number, file_number, (Tox_File_Control)control, &error);

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)error;
    }

    return ok && error == TOX_ERR_FILE_CONTROL_OK;
}

bool toxw_file_send_chunk(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t file_number,
    uint64_t position,
    const uint8_t *data,
    size_t length,
    int32_t *out_error_code
) {
    if (wrapper == NULL || wrapper->tox == NULL) {
        if (out_error_code != NULL) {
            *out_error_code = -1;
        }
        return false;
    }

    Tox_Err_File_Send_Chunk error = TOX_ERR_FILE_SEND_CHUNK_OK;
    const bool ok = tox_file_send_chunk(wrapper->tox, friend_number, file_number, position, data, length, &error);

    if (out_error_code != NULL) {
        *out_error_code = (int32_t)error;
    }

    return ok && error == TOX_ERR_FILE_SEND_CHUNK_OK;
}