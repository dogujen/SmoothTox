#ifndef TOX_WRAPPER_H
#define TOX_WRAPPER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct ToxWrapper ToxWrapper;

typedef void (*toxw_self_connection_status_cb)(void *swift_user_data, uint32_t connection_status);
typedef void (*toxw_friend_connection_status_cb)(void *swift_user_data, uint32_t friend_number, uint32_t connection_status);
typedef void (*toxw_friend_name_cb)(void *swift_user_data, uint32_t friend_number, const uint8_t *name, size_t length);
typedef void (*toxw_friend_message_cb)(void *swift_user_data, uint32_t friend_number, const uint8_t *message, size_t length);
typedef void (*toxw_friend_request_cb)(void *swift_user_data, const uint8_t *public_key_32, const uint8_t *message, size_t length);
typedef void (*toxw_file_recv_cb)(void *swift_user_data, uint32_t friend_number, uint32_t file_number, uint32_t kind, uint64_t file_size, const uint8_t *filename, size_t filename_length);
typedef void (*toxw_file_recv_chunk_cb)(void *swift_user_data, uint32_t friend_number, uint32_t file_number, uint64_t position, const uint8_t *data, size_t length);
typedef void (*toxw_file_chunk_request_cb)(void *swift_user_data, uint32_t friend_number, uint32_t file_number, uint64_t position, size_t length);
typedef void (*toxw_file_recv_control_cb)(void *swift_user_data, uint32_t friend_number, uint32_t file_number, uint32_t control);
typedef void (*toxw_group_message_cb)(void *swift_user_data, uint32_t group_number, uint32_t peer_id, const uint8_t *message, size_t message_length);
typedef void (*toxw_group_invite_cb)(void *swift_user_data, uint32_t friend_number, const uint8_t *invite_data, size_t invite_data_length, const uint8_t *group_name, size_t group_name_length);
typedef void (*toxw_group_peer_name_cb)(void *swift_user_data, uint32_t group_number, uint32_t peer_id, const uint8_t *name, size_t name_length);
typedef void (*toxw_group_peer_join_cb)(void *swift_user_data, uint32_t group_number, uint32_t peer_id);
typedef void (*toxw_group_peer_exit_cb)(void *swift_user_data, uint32_t group_number, uint32_t peer_id);
typedef void (*toxw_group_custom_private_packet_cb)(void *swift_user_data, uint32_t group_number, uint32_t peer_id, const uint8_t *data, size_t data_length);
typedef void (*toxw_av_call_cb)(void *swift_user_data, uint32_t friend_number, bool audio_enabled, bool video_enabled);
typedef void (*toxw_av_call_state_cb)(void *swift_user_data, uint32_t friend_number, uint32_t state);
typedef void (*toxw_av_audio_frame_cb)(void *swift_user_data, uint32_t friend_number, const int16_t *pcm, size_t sample_count, uint8_t channels, uint32_t sampling_rate);

ToxWrapper *toxw_create(int32_t *out_error_code);
ToxWrapper *toxw_create_from_savedata(const uint8_t *savedata, size_t savedata_length, int32_t *out_error_code);
ToxWrapper *toxw_create_with_proxy(
    const uint8_t *savedata,
    size_t savedata_length,
    uint32_t proxy_type,
    const char *proxy_host,
    uint16_t proxy_port,
    int32_t *out_error_code
);
void toxw_destroy(ToxWrapper *wrapper);

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
);

void toxw_set_av_callbacks(
    ToxWrapper *wrapper,
    toxw_av_call_cb av_call_callback,
    toxw_av_call_state_cb av_call_state_callback,
    toxw_av_audio_frame_cb av_audio_frame_callback
);

void toxw_set_group_callbacks(
    ToxWrapper *wrapper,
    toxw_group_message_cb group_message_callback,
    toxw_group_invite_cb group_invite_callback,
    toxw_group_peer_name_cb group_peer_name_callback,
    toxw_group_peer_join_cb group_peer_join_callback,
    toxw_group_peer_exit_cb group_peer_exit_callback,
    toxw_group_custom_private_packet_cb group_custom_private_packet_callback
);

void toxw_iterate(ToxWrapper *wrapper);
uint32_t toxw_iteration_interval_ms(const ToxWrapper *wrapper);

bool toxw_bootstrap(ToxWrapper *wrapper, const char *host, uint16_t port, const uint8_t *public_key_32, int32_t *out_error_code);

bool toxw_get_self_address(const ToxWrapper *wrapper, uint8_t *out_address_38);
bool toxw_set_self_name(ToxWrapper *wrapper, const uint8_t *name, size_t length, int32_t *out_error_code);
bool toxw_get_self_name(const ToxWrapper *wrapper, uint8_t *out_name, size_t *inout_length);
size_t toxw_get_savedata_size(const ToxWrapper *wrapper);
bool toxw_get_savedata(const ToxWrapper *wrapper, uint8_t *out_savedata, size_t capacity, size_t *out_written);

uint32_t toxw_get_friend_count(const ToxWrapper *wrapper);
uint32_t toxw_get_friend_list(const ToxWrapper *wrapper, uint32_t *out_friend_numbers, uint32_t capacity);
bool toxw_get_friend_name(const ToxWrapper *wrapper, uint32_t friend_number, uint8_t *out_name, size_t *inout_length);
bool toxw_get_friend_public_key(const ToxWrapper *wrapper, uint32_t friend_number, uint8_t *out_public_key_32);

bool toxw_send_message(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    const uint8_t *message,
    size_t message_length,
    uint32_t *out_message_id,
    int32_t *out_error_code
);

bool toxw_add_friend_norequest(
    ToxWrapper *wrapper,
    const uint8_t *public_key_32,
    uint32_t *out_friend_number,
    int32_t *out_error_code
);

bool toxw_add_friend(
    ToxWrapper *wrapper,
    const uint8_t *address_38,
    const uint8_t *message,
    size_t message_length,
    uint32_t *out_friend_number,
    int32_t *out_error_code
);

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
);

bool toxw_file_control(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t file_number,
    uint32_t control,
    int32_t *out_error_code
);

bool toxw_file_send_chunk(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t file_number,
    uint64_t position,
    const uint8_t *data,
    size_t length,
    int32_t *out_error_code
);

bool toxw_av_call(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t audio_bit_rate,
    uint32_t video_bit_rate,
    int32_t *out_error_code
);

bool toxw_av_answer(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t audio_bit_rate,
    uint32_t video_bit_rate,
    int32_t *out_error_code
);

bool toxw_av_call_control(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    uint32_t control,
    int32_t *out_error_code
);

bool toxw_av_audio_send_frame(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    const int16_t *pcm,
    size_t sample_count,
    uint8_t channels,
    uint32_t sampling_rate,
    int32_t *out_error_code
);

uint32_t toxw_group_chat_id_size(void);

bool toxw_group_new_public(
    ToxWrapper *wrapper,
    const uint8_t *group_name,
    size_t group_name_length,
    const uint8_t *self_name,
    size_t self_name_length,
    uint32_t *out_group_number,
    int32_t *out_error_code
);

bool toxw_group_join_by_chat_id(
    ToxWrapper *wrapper,
    const uint8_t *chat_id,
    size_t chat_id_length,
    const uint8_t *self_name,
    size_t self_name_length,
    uint32_t *out_group_number,
    int32_t *out_error_code
);

bool toxw_group_leave(
    ToxWrapper *wrapper,
    uint32_t group_number,
    int32_t *out_error_code
);

uint32_t toxw_group_chatlist_size(const ToxWrapper *wrapper);

uint32_t toxw_group_chatlist(
    const ToxWrapper *wrapper,
    uint32_t *out_group_numbers,
    uint32_t capacity
);

bool toxw_group_get_chat_id(
    const ToxWrapper *wrapper,
    uint32_t group_number,
    uint8_t *out_chat_id,
    int32_t *out_error_code
);

bool toxw_group_send_message(
    ToxWrapper *wrapper,
    uint32_t group_number,
    const uint8_t *message,
    size_t message_length,
    int32_t *out_error_code
);

bool toxw_group_send_custom_private_packet(
    ToxWrapper *wrapper,
    uint32_t group_number,
    uint32_t peer_id,
    bool lossless,
    const uint8_t *data,
    size_t data_length,
    int32_t *out_error_code
);

bool toxw_group_is_public(
    const ToxWrapper *wrapper,
    uint32_t group_number,
    bool *out_is_public,
    int32_t *out_error_code
);

bool toxw_group_peer_get_name(
    const ToxWrapper *wrapper,
    uint32_t group_number,
    uint32_t peer_id,
    uint8_t *out_name,
    size_t *inout_length
);

bool toxw_group_peer_get_public_key(
    const ToxWrapper *wrapper,
    uint32_t group_number,
    uint32_t peer_id,
    uint8_t *out_public_key_32
);

bool toxw_group_self_get_public_key(
    const ToxWrapper *wrapper,
    uint32_t group_number,
    uint8_t *out_public_key_32
);

bool toxw_group_invite_accept(
    ToxWrapper *wrapper,
    uint32_t friend_number,
    const uint8_t *invite_data,
    size_t invite_data_length,
    const uint8_t *self_name,
    size_t self_name_length,
    uint32_t *out_group_number,
    int32_t *out_error_code
);

#endif